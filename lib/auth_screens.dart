import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app_routes.dart';
import 'services/auth_api_service.dart';
import 'services/storage_service.dart';
import 'services/attendance_service_factory.dart';

// Splash Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();

    Future.delayed(Duration(seconds: 3), () async {
      if (!mounted) return;
      // Check if user is already logged in
      final isLoggedIn = await StorageService.isLoggedIn();
      if (!mounted) return;
      if (isLoggedIn) {
        // Restore login state
        final token = await StorageService.getAuthToken();
        final user = await StorageService.getUserData();
        if (!mounted) return;
        if (token != null && user != null) {
          // Restore in AuthApiService
          AuthApiService.restoreLoginState(token: token, user: user);
          
          // Don't initialize attendance service here - let SafeStartupManager handle it
          // This prevents crashes from starting services before permissions are ready
          debugPrint('[SplashScreen] Skipping service initialization - will be handled by SafeStartupManager');
          
          if (mounted) {
            Navigator.pushReplacementNamed(context, AppRoutes.main);
          }
          return;
        }
      }
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8F9FA),
              Colors.white,
            ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                          ),
                        child: ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(15.0),
                          child: Image.asset(
                              'assets/toai_attend_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 30),
                      Text(
                        'Smart Attendance Solution',
                        style: TextStyle(
                          fontSize: 16,
                          color: const Color(0xFF6B7280),
                          letterSpacing: 1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// Login Screen
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthApiService _authApiService = AuthApiService();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _isGoogleSigningIn = false;

  @override
  void dispose() {
    _authApiService.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await _authApiService.login(
        LoginRequest(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ),
      );

      if (!mounted) return;

      // Save login state for persistent login
      await StorageService.saveLoginState(
        token: response.token,
        user: response.user,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, ${response.user.name}!'),
        ),
      );

      if (!mounted) return;
      
      await AttendanceServiceFactory.reset();
      try {
        await AttendanceServiceFactory.initializeController();
      } catch (e) {
        debugPrint('[AuthScreen] Attendance initialization failed: $e');
      }
      
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    } on AuthApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleSigningIn = true);

    try {
      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled the sign-in
        if (mounted) {
          setState(() => _isGoogleSigningIn = false);
        }
        return;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Get the ID token
      final String? idToken = googleAuth.idToken;
      
      if (idToken == null) {
        throw Exception('Failed to get Google ID token');
      }

      // Send ID token to backend
      final response = await _authApiService.loginWithGoogle(idToken);

      if (!mounted) return;

      // Save login state for persistent login
      await StorageService.saveLoginState(
        token: response.token,
        user: response.user,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, ${response.user.name}!'),
        ),
      );

      if (!mounted) return;
      
      await AttendanceServiceFactory.reset();
      try {
        await AttendanceServiceFactory.initializeController();
      } catch (e) {
        debugPrint('[AuthScreen] Attendance initialization failed: $e');
      }
      
      Navigator.pushReplacementNamed(context, AppRoutes.main);
    } on AuthApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('Google sign-in failed: ${error.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isGoogleSigningIn = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8F9FA),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  SizedBox(height: 50),
                  Hero(
                    tag: 'logo',
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 15,
                            spreadRadius: 3,
                          ),
                        ],
                        ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                        child: Image.asset(
                            'assets/toai_attend_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 30),
                  Text(
                    'Welcome Back!',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Sign in to continue',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 50),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          style: TextStyle(color: Colors.black87),
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: TextStyle(color: Colors.grey[700]),
                            prefixIcon: Icon(Icons.person_outline, color: Colors.grey[700]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(color: Colors.blue, width: 1),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: TextStyle(color: Colors.grey[700]),
                            prefixIcon: Icon(Icons.lock_outline, color: Colors.grey[700]),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.grey[700],
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(color: Colors.blue, width: 1),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 30),
                        Container(
                          width: double.infinity,
                          height: 55,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF2563EB),
                                Color(0xFF3B82F6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withOpacity(0.4),
                                blurRadius: 16,
                                spreadRadius: 0,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: _isSubmitting
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _departmentController = TextEditingController();
  final _designationController = TextEditingController();
  final _managerIdController = TextEditingController();

  final List<String> _roles = ['manager', 'employee', 'admin'];

  final AuthApiService _authApiService = AuthApiService();
  String _selectedRole = 'manager';
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _authApiService.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _departmentController.dispose();
    _designationController.dispose();
    _managerIdController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[700]),
      prefixIcon: Icon(icon, color: Colors.grey[700]),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Colors.grey[100],
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.blue, width: 1),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    final request = RegisterRequest(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      role: _selectedRole,
      department: _departmentController.text.trim(),
      designation: _designationController.text.trim(),
      managerId: _managerIdController.text.trim(),
    );

    try {
      final registeredUser = await _authApiService.registerUser(request);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registered ${registeredUser.email} successfully!'),
        ),
      );
      Navigator.pop(context);
    } on AuthApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
        title: Text('Register', style: TextStyle(color: Colors.black87)),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8F9FA),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create a new account',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    style: TextStyle(color: Colors.black87),
                    decoration: _inputDecoration('Full Name', Icons.person_outline),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Name is required'
                        : null,
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: Colors.black87),
                    decoration: _inputDecoration('Email', Icons.email_outlined),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(color: Colors.black87),
                    decoration: _inputDecoration('Password', Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey[700],
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    dropdownColor: Colors.white,
                    style: TextStyle(color: Colors.black87),
                    decoration: _inputDecoration('Role', Icons.badge_outlined),
                    items: _roles
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(
                              role.toUpperCase(),
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedRole = value);
                      }
                    },
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _departmentController,
                    style: TextStyle(color: Colors.black87),
                    decoration:
                        _inputDecoration('Department', Icons.apartment_outlined),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Department is required'
                        : null,
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _designationController,
                    style: TextStyle(color: Colors.black87),
                    decoration:
                        _inputDecoration('Designation', Icons.workspace_premium_outlined),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Designation is required'
                        : null,
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _managerIdController,
                    style: TextStyle(color: Colors.black87),
                    decoration:
                        _inputDecoration('Manager ID', Icons.confirmation_number_outlined),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Manager ID is required'
                        : null,
                  ),
                  SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSubmitting ? Colors.grey : Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Register',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}