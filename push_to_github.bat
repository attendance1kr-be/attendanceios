@echo off
echo ===================================================
echo     PUSH ATTENDANCE APP TO GITHUB
echo ===================================================
echo.
set /p REPO_URL="Enter your GitHub Repository URL: "

if "%REPO_URL%"=="" (
    echo Error: No repository URL provided!
    pause
    exit /b
)

echo.
echo 1. Configuring Git User Identity...
git config --global user.email "attendance1kr@gmail.com"
git config --global user.name "attendancelkr-be"
git config user.email "attendance1kr@gmail.com"
git config user.name "attendancelkr-be"

echo 2. Erasing Old Saved Logins...
cmd /c "echo protocol=https&echo host=github.com&echo. | git credential erase" 2>nul

echo 3. Initializing Local Git Repository...
git init

echo 4. Adding Files...
git add .

echo 5. Creating Commit...
git commit -m "Initial commit - Clean Staff Tracker Source Code" 2>nul

echo 6. Configuring Remote Repository...
git branch -M main
git remote remove origin 2>nul
git remote add origin %REPO_URL%

echo 7. Uploading Code to GitHub...
echo.
echo NOTE: If a login window opens, log in with: attendance1kr@gmail.com
echo.
git push -u origin main --force

if %errorlevel% neq 0 (
    echo.
    echo ---------------------------------------------------
    echo ERROR: Push failed.
    echo.
    echo IMPORTANT: Make sure you have CREATED the repository on GitHub first!
    echo 1. Go to https://github.com
    echo 2. Log in with account: attendance1kr@gmail.com
    echo 3. Click "+" on top right -> "New repository"
    echo 4. Repository Name: attendanceios (or attendance)
    echo 5. Click "Create repository"
    echo 6. Copy the URL and paste it here in this script!
    echo ---------------------------------------------------
) else (
    echo.
    echo ===================================================
    echo SUCCESS! Your project is now uploaded to GitHub!
    echo ===================================================
)
pause
