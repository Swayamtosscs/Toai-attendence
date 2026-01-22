# ToAI Attendance - Premium Dashboard

A modern, premium dashboard for ToAI Attendance app with dark mode support.

## Features

- 🎨 Premium UI/UX design inspired by Apple, Stripe, Notion, Linear
- 🌙 Dark mode with smooth transitions
- 📱 Fully responsive design
- ⚡ Fast and optimized
- 🎯 Clean, modern interface

## Tech Stack

- HTML5
- CSS3 (with CSS Variables)
- Vanilla JavaScript
- Inter Font Family

## Deployment on Vercel

### Method 1: Deploy via GitHub (Recommended)

1. Push your code to GitHub repository
2. Go to [Vercel](https://vercel.com)
3. Sign in with your GitHub account
4. Click "New Project"
5. Import your GitHub repository: `Swayamtosscs/Toai-attendence`
6. Vercel will auto-detect the configuration
7. Click "Deploy"

### Method 2: Deploy via Vercel CLI

```bash
# Install Vercel CLI
npm i -g vercel

# Login to Vercel
vercel login

# Deploy
vercel

# For production deployment
vercel --prod
```

## Project Structure

```
.
├── index.html          # Main HTML file
├── styles.css          # All styles with dark mode
├── script.js           # JavaScript functionality
├── public/             # Images and assets
│   ├── App logo.png
│   ├── Home.png
│   ├── Splash screen .png
│   └── ...
├── assest/             # APK file
│   └── app-release.apk
├── vercel.json         # Vercel configuration
└── README.md           # This file
```

## Configuration

The `vercel.json` file is configured to:
- Handle all routes and redirect to `index.html` (for SPA routing)
- Set proper cache headers for static assets
- Configure APK file downloads

## Live Demo

After deployment, your site will be available at:
`https://your-project-name.vercel.app`

## Repository

GitHub: [https://github.com/Swayamtosscs/Toai-attendence](https://github.com/Swayamtosscs/Toai-attendence)

## License

All rights reserved.

