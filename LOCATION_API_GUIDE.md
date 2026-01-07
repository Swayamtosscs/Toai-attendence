# Location Save API Implementation Guide

## Backend API Endpoint Required

### 1. POST /api/work-locations (Create New Location)

**Endpoint:** `POST http://103.14.120.163:8092/api/work-locations`

**Authentication:** Required (Bearer Token)
- Header: `Authorization: Bearer <token>`
- Cookie: `attendance_token=<token>` (optional)

**Request Body:**
```json
{
  "name": "Main Office",
  "latitude": 22.3072,
  "longitude": 73.1812,
  "radius": 100.0
}
```

**Request Fields:**
- `name` (string, required): Location name (e.g., "Main Office", "Branch Office")
- `latitude` (number, required): Latitude coordinate (-90 to 90)
- `longitude` (number, required): Longitude coordinate (-180 to 180)
- `radius` (number, required): Geofence radius in meters (1 to 10000)

**Success Response (200/201):**
```json
{
  "success": true,
  "message": "Location saved successfully",
  "data": {
    "id": "loc_123456789",
    "name": "Main Office",
    "latitude": 22.3072,
    "longitude": 73.1812,
    "radius": 100.0,
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T10:30:00Z"
  }
}
```

**Error Responses:**

**400 Bad Request** (Validation Error):
```json
{
  "success": false,
  "message": "Invalid location data",
  "error": "Latitude must be between -90 and 90"
}
```

**401 Unauthorized** (No Token):
```json
{
  "success": false,
  "message": "Authentication required"
}
```

**500 Internal Server Error**:
```json
{
  "success": false,
  "message": "Failed to save location",
  "error": "Database error"
}
```

---

### 2. PUT /api/work-locations/:id (Update Existing Location)

**Endpoint:** `PUT http://103.14.120.163:8092/api/work-locations/:id`

**Authentication:** Required (Bearer Token)

**Request Body:** Same as POST

**Success Response (200):**
```json
{
  "success": true,
  "message": "Location updated successfully",
  "data": {
    "id": "loc_123456789",
    "name": "Updated Office Name",
    "latitude": 22.3072,
    "longitude": 73.1812,
    "radius": 150.0,
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T11:45:00Z"
  }
}
```

---

### 3. GET /api/work-locations (Get All Locations)

**Endpoint:** `GET http://103.14.120.163:8092/api/work-locations`

**Authentication:** Required (Bearer Token)

**Success Response (200):**
```json
{
  "success": true,
  "data": {
    "locations": [
      {
        "id": "loc_123456789",
        "name": "Main Office",
        "latitude": 22.3072,
        "longitude": 73.1812,
        "radius": 100.0
      },
      {
        "id": "loc_987654321",
        "name": "Branch Office",
        "latitude": 22.3500,
        "longitude": 73.2000,
        "radius": 150.0
      }
    ]
  }
}
```

**Note:** Current implementation expects response format:
```json
{
  "locations": [...]
}
```

---

### 4. DELETE /api/work-locations/:id (Delete Location)

**Endpoint:** `DELETE http://103.14.120.163:8092/api/work-locations/:id`

**Authentication:** Required (Bearer Token)

**Success Response (200):**
```json
{
  "success": true,
  "message": "Location deleted successfully"
}
```

---

## Database Schema Required

### Work Locations Table

**Table Name:** `work_locations` or `locations`

**Fields:**
```sql
CREATE TABLE work_locations (
  id VARCHAR(255) PRIMARY KEY,           -- Unique location ID
  name VARCHAR(255) NOT NULL,          -- Location name
  latitude DECIMAL(10, 8) NOT NULL,     -- Latitude (-90 to 90)
  longitude DECIMAL(11, 8) NOT NULL,    -- Longitude (-180 to 180)
  radius DECIMAL(10, 2) NOT NULL,       -- Radius in meters
  created_by VARCHAR(255),              -- User ID who created (optional)
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE         -- Soft delete flag
);

-- Indexes for better performance
CREATE INDEX idx_latitude_longitude ON work_locations(latitude, longitude);
CREATE INDEX idx_created_by ON work_locations(created_by);
```

**MongoDB Schema (if using MongoDB):**
```javascript
{
  _id: ObjectId,
  id: String,              // Unique location ID
  name: String,            // Location name
  latitude: Number,        // Latitude
  longitude: Number,       // Longitude
  radius: Number,          // Radius in meters
  createdBy: String,       // User ID (optional)
  createdAt: Date,
  updatedAt: Date,
  isActive: Boolean         // Default: true
}
```

---

## Backend Implementation Example

### Node.js/Express Example

```javascript
// POST /api/work-locations
router.post('/work-locations', authenticateToken, async (req, res) => {
  try {
    const { name, latitude, longitude, radius } = req.body;
    const userId = req.user.id; // From JWT token

    // Validation
    if (!name || !latitude || !longitude || !radius) {
      return res.status(400).json({
        success: false,
        message: 'All fields are required'
      });
    }

    if (latitude < -90 || latitude > 90) {
      return res.status(400).json({
        success: false,
        message: 'Latitude must be between -90 and 90'
      });
    }

    if (longitude < -180 || longitude > 180) {
      return res.status(400).json({
        success: false,
        message: 'Longitude must be between -180 and 180'
      });
    }

    if (radius <= 0 || radius > 10000) {
      return res.status(400).json({
        success: false,
        message: 'Radius must be between 1 and 10000 meters'
      });
    }

    // Create location
    const location = {
      id: `loc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      name,
      latitude,
      longitude,
      radius,
      createdBy: userId,
      createdAt: new Date(),
      updatedAt: new Date(),
      isActive: true
    };

    // Save to database
    const savedLocation = await LocationModel.create(location);

    res.status(201).json({
      success: true,
      message: 'Location saved successfully',
      data: savedLocation
    });

  } catch (error) {
    console.error('Error saving location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to save location',
      error: error.message
    });
  }
});

// GET /api/work-locations
router.get('/work-locations', authenticateToken, async (req, res) => {
  try {
    const locations = await LocationModel.find({ isActive: true });
    
    res.status(200).json({
      locations: locations.map(loc => ({
        id: loc.id,
        name: loc.name,
        latitude: loc.latitude,
        longitude: loc.longitude,
        radius: loc.radius
      }))
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch locations',
      error: error.message
    });
  }
});

// PUT /api/work-locations/:id
router.put('/work-locations/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, latitude, longitude, radius } = req.body;

    // Validation (same as POST)

    const updatedLocation = await LocationModel.findOneAndUpdate(
      { id, isActive: true },
      {
        name,
        latitude,
        longitude,
        radius,
        updatedAt: new Date()
      },
      { new: true }
    );

    if (!updatedLocation) {
      return res.status(404).json({
        success: false,
        message: 'Location not found'
      });
    }

    res.status(200).json({
      success: true,
      message: 'Location updated successfully',
      data: updatedLocation
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to update location',
      error: error.message
    });
  }
});

// DELETE /api/work-locations/:id
router.delete('/work-locations/:id', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;

    const location = await LocationModel.findOneAndUpdate(
      { id, isActive: true },
      { isActive: false, updatedAt: new Date() },
      { new: true }
    );

    if (!location) {
      return res.status(404).json({
        success: false,
        message: 'Location not found'
      });
    }

    res.status(200).json({
      success: true,
      message: 'Location deleted successfully'
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to delete location',
      error: error.message
    });
  }
});
```

---

## Python/Flask Example

```python
from flask import Flask, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity

@app.route('/api/work-locations', methods=['POST'])
@jwt_required()
def create_location():
    try:
        data = request.get_json()
        name = data.get('name')
        latitude = data.get('latitude')
        longitude = data.get('longitude')
        radius = data.get('radius')
        user_id = get_jwt_identity()

        # Validation
        if not all([name, latitude, longitude, radius]):
            return jsonify({
                'success': False,
                'message': 'All fields are required'
            }), 400

        if not (-90 <= latitude <= 90):
            return jsonify({
                'success': False,
                'message': 'Latitude must be between -90 and 90'
            }), 400

        if not (-180 <= longitude <= 180):
            return jsonify({
                'success': False,
                'message': 'Longitude must be between -180 and 180'
            }), 400

        if not (1 <= radius <= 10000):
            return jsonify({
                'success': False,
                'message': 'Radius must be between 1 and 10000 meters'
            }), 400

        # Create location
        location = {
            'id': f"loc_{int(time.time())}_{random_string(9)}",
            'name': name,
            'latitude': latitude,
            'longitude': longitude,
            'radius': radius,
            'created_by': user_id,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow(),
            'is_active': True
        }

        # Save to database
        location_id = db.locations.insert_one(location).inserted_id

        return jsonify({
            'success': True,
            'message': 'Location saved successfully',
            'data': location
        }), 201

    except Exception as e:
        return jsonify({
            'success': False,
            'message': 'Failed to save location',
            'error': str(e)
        }), 500
```

---

## Important Points

1. **Authentication:** All endpoints must require authentication (Bearer token)
2. **Validation:** Validate all input fields before saving
3. **Error Handling:** Return proper error messages
4. **Response Format:** Follow the exact response format shown above
5. **Database:** Use soft delete (isActive flag) instead of hard delete
6. **User Association:** Optionally track which user created the location

---

## Testing the API

### Using cURL:

```bash
# Create Location
curl -X POST http://103.14.120.163:8092/api/work-locations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "name": "Main Office",
    "latitude": 22.3072,
    "longitude": 73.1812,
    "radius": 100.0
  }'

# Get All Locations
curl -X GET http://103.14.120.163:8092/api/work-locations \
  -H "Authorization: Bearer YOUR_TOKEN"

# Update Location
curl -X PUT http://103.14.120.163:8092/api/work-locations/loc_123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "name": "Updated Office",
    "latitude": 22.3072,
    "longitude": 73.1812,
    "radius": 150.0
  }'

# Delete Location
curl -X DELETE http://103.14.120.163:8092/api/work-locations/loc_123 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## After Backend is Ready

Once you've created the backend API, I'll update the Flutter app to:
1. Call the API when saving locations
2. Save to both backend and local storage (as backup)
3. Load locations from backend first, then fallback to local storage

Let me know when your backend API is ready!

