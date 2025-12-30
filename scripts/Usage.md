# Interactive mode
sudo ./build.sh --interactive

# Minimal build with custom settings
sudo ./build.sh --profile minimal --user myuser --hostname MyOS

# Developer edition with parallel builds
sudo ./build.sh --profile developer --jobs 8 --compression 6

# Sign ISO with GPG
sudo ./build.sh --sign --backup --verbose

# Server edition with testing repo
sudo ./build.sh --profile server --testing --clean

# List available profiles
./build.sh --list-profiles

# Show version
./build.sh --version
