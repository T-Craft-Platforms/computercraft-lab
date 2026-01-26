import sys
import json
import subprocess
import platform
import urllib.request
import shutil
import zipfile
import argparse
from pathlib import Path

# Configuration
CRAFTOS_BASE_DIR = "craftos-pc"
CRAFTOSPC_URL = (
    "https://github.com/MCJack123/craftos2/releases/download/"
    "v2.8.3/CraftOS-PC-Portable-Win64.zip"
)

# Global variables
CODE_PATH = None

def check_vscode_installed():
    """Check if VSCode is installed and set global CODE_PATH."""
    global CODE_PATH
    CODE_PATH = shutil.which("code")
    if not CODE_PATH:
        return False

    try:
        result = subprocess.run(
            [CODE_PATH, "--version"],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, Exception):
        return False

def get_installed_extensions():
    """Get list of currently installed VSCode extensions."""
    if not CODE_PATH:
        return []
    
    try:
        result = subprocess.run(
            [CODE_PATH, "--list-extensions"],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0:
            return [ext.strip().lower() for ext in result.stdout.strip().split('\n') if ext.strip()]
    except (subprocess.TimeoutExpired, Exception) as e:
        print(f"⚠ Error getting installed extensions: {e}")
    
    return []

def update_vscode_settings(install_path):
    """Update .vscode/settings.json with project path."""
    vscode_dir = Path('.vscode')
    vscode_dir.mkdir(exist_ok=True)
    
    settings_file = vscode_dir / 'settings.json'
    craftos_data_path = str((Path.cwd() / CRAFTOS_BASE_DIR).resolve())
    
    settings = {}
    if settings_file.exists():
        try:
            with open(settings_file, 'r', encoding='utf-8') as f:
                settings = json.load(f)
        except json.JSONDecodeError:
            print("⚠ Warning: Invalid JSON in settings.json, creating new file")
    
    settings['craftos-pc.dataPath'] = craftos_data_path
    
    if install_path:
        executable_path = str((Path(install_path) / 'CraftOS-PC_console.exe').resolve())
        settings['craftos-pc.executablePath.windows'] = executable_path
    
    try:
        with open(settings_file, 'w', encoding='utf-8') as f:
            json.dump(settings, f, indent=2)
        print(f"✓ Updated .vscode/settings.json")
    except Exception as e:
        print(f"⚠ Error updating settings.json: {e}")

def install_vscode_extensions():
    """Install VSCode extensions from extensions.json."""
    if not CODE_PATH:
        print("⚠ VSCode not available, skipping extension installation")
        return
    
    extensions_file = Path('.vscode') / 'extensions.json'
    
    if not extensions_file.exists():
        print("⚠ extensions.json not found")
        return
    
    try:
        with open(extensions_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"⚠ Error reading extensions.json: {e}")
        return
    
    extensions = data.get('recommendations', [])
    if not extensions:
        print("⚠ No extensions found in extensions.json")
        return
    
    # Check which extensions are already installed
    installed = get_installed_extensions()
    missing_extensions = [ext for ext in extensions if ext.lower() not in installed]
    
    if not missing_extensions:
        print(f"✓ All {len(extensions)} extensions are already installed")
        return
    
    print(f"\nMissing extensions ({len(missing_extensions)}):")
    for ext in missing_extensions:
        print(f"  - {ext}")
    
    response = input(f"\nInstall {len(missing_extensions)} missing extension(s)? (y/n): ").strip().lower()
    if response != 'y':
        print("Skipping extension installation")
        return
    
    for ext in missing_extensions:
        print(f"Installing {ext}...")
        try:
            result = subprocess.run(
                [CODE_PATH, '--install-extension', ext],
                capture_output=True,
                text=True,
                timeout=120
            )
            if result.returncode == 0:
                print(f"  ✓ {ext} installed")
            else:
                print(f"  ⚠ Failed to install {ext}: {result.stderr.strip()}")
        except subprocess.TimeoutExpired:
            print(f"  ⚠ Timeout installing {ext}")
        except Exception as e:
            print(f"  ⚠ Error installing {ext}: {e}")

def download_craftospc():
    """Download and extract CraftOS-PC (Windows only)."""
    base_dir = Path(CRAFTOS_BASE_DIR)
    lib_dir = base_dir / 'lib'
    downloads_dir = lib_dir / "_downloads"
    craftospc_dir = lib_dir / "CraftOS-PC"
    zip_path = downloads_dir / "craftospc.zip"
    
    if craftospc_dir.is_dir() and any(craftospc_dir.iterdir()):
        print(f"✓ CraftOS-PC already exists at {craftospc_dir}")
        return str(craftospc_dir.resolve())
    
    if platform.system() != "Windows":
        print("\n⚠ CraftOS-PC automatic download is only supported on Windows")
        print("  Install manually: https://www.craftos-pc.cc/docs/installation")
        return None
    
    base_dir.mkdir(exist_ok=True)
    downloads_dir.mkdir(parents=True, exist_ok=True)
    
    print("\nDownloading CraftOS-PC...")
    try:
        urllib.request.urlretrieve(CRAFTOSPC_URL, zip_path)
        print("✓ Download complete")
        
        craftospc_dir.mkdir(parents=True, exist_ok=True)

        print("Extracting...")
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(craftospc_dir)
        
        zip_path.unlink()
        print(f"✓ CraftOS-PC extracted to {craftospc_dir}")

        return str(craftospc_dir.resolve())
        
    except urllib.error.URLError as e:
        print(f"⚠ Network error downloading CraftOS-PC: {e}")
    except zipfile.BadZipFile:
        print("⚠ Downloaded file is not a valid zip archive")
        if zip_path.exists():
            zip_path.unlink()
    except Exception as e:
        print(f"⚠ Error downloading/extracting CraftOS-PC: {e}")

    return None

def get_computer_dir(computer_id):
    """Get the path to a specific computer directory."""
    return Path(CRAFTOS_BASE_DIR) / "computer" / str(computer_id)

def link_command(computer_id):
    """Link a computer ID to the project's src directory."""
    computer_dir = get_computer_dir(computer_id)
    src_dir = Path.cwd() / "src"
    
    # Ensure src directory exists
    if not src_dir.exists():
        print(f"⚠ Source directory 'src' does not exist in {Path.cwd()}")
        response = input("Create src directory? (y/n): ").strip().lower()
        if response == 'y':
            src_dir.mkdir(parents=True, exist_ok=True)
            print(f"✓ Created {src_dir}")
        else:
            return False
    
    # Ensure base directory exists
    base_dir = Path(CRAFTOS_BASE_DIR)
    if not base_dir.exists():
        print(f"⚠ CraftOS directory '{CRAFTOS_BASE_DIR}' does not exist. Run 'setup' first.")
        return False
    
    # Create computer directory if it doesn't exist
    computer_dir.parent.mkdir(parents=True, exist_ok=True)
    
    # Check if link already exists
    if computer_dir.exists():
        if computer_dir.is_symlink():
            target = computer_dir.resolve()
            if target == src_dir.resolve():
                print(f"✓ Computer {computer_id} is already linked to src directory")
                return True
            else:
                print(f"⚠ Computer {computer_id} is linked to different directory: {target}")
                response = input("Overwrite? (y/n): ").strip().lower()
                if response != 'y':
                    return False
                computer_dir.unlink()
        else:
            print(f"⚠ Computer {computer_id} exists but is not a symlink")
            response = input("Remove and create link? (y/n): ").strip().lower()
            if response != 'y':
                return False
            shutil.rmtree(computer_dir)
    
    # Create symlink
    try:
        computer_dir.symlink_to(src_dir, target_is_directory=True)
        print(f"✓ Linked computer {computer_id} to {src_dir}")
        return True
    except OSError as e:
        print(f"⚠ Error creating symlink: {e}")
        if platform.system() == "Windows":
            print("  Note: On Windows, you may need administrator privileges or Developer Mode enabled")
        return False

def unlink_command(computer_id):
    """Unlink a computer ID from the project directory."""
    computer_dir = get_computer_dir(computer_id)
    
    if not computer_dir.exists():
        print(f"⚠ Computer {computer_id} does not exist")
        return False
    
    if not computer_dir.is_symlink():
        print(f"⚠ Computer {computer_id} is not a symlink")
        response = input("Delete anyway? (y/n): ").strip().lower()
        if response != 'y':
            return False
        shutil.rmtree(computer_dir)
        print(f"✓ Removed computer {computer_id} directory")
        return True
    
    try:
        target = computer_dir.resolve()
        computer_dir.unlink()
        print(f"✓ Unlinked computer {computer_id} (was linked to {target})")
        return True
    except OSError as e:
        print(f"⚠ Error removing symlink: {e}")
        return False

def setup_command():
    """Run the initial setup process."""
    print("=== Repository Setup ===\n")
    
    # Check VSCode
    vscode_installed = check_vscode_installed()
    if not vscode_installed:
        print("⚠ WARNING: VSCode is not installed or 'code' command is not in PATH")
        print("Please install VSCode from: https://code.visualstudio.com/")
        response = input("\nContinue anyway? (y/n): ").strip().lower()
        if response != 'y':
            sys.exit(1)
    else:
        print("✓ VSCode is installed")
    
    # Install extensions
    if vscode_installed:
        install_vscode_extensions()
    
    # Check Operating System
    system = platform.system()
    print(f"\nDetected Operating System: {system}")
    
    # Download CraftOS-PC
    install_path = download_craftospc()

    # Update settings
    update_vscode_settings(install_path)
    
    print("\nIt may be necessary to restart VSCode for changes to take effect.")
    print("\n=== Setup Complete ===")

    # Prompt to link default computer
    print("\nTo use CraftOS-PC with this project, you need to link a computer ID.")
    response = input("\nLink computer 0 now? (y/n): ").strip().lower()
    if response == 'y':
        print()
        link_command(0)
    else:
        print("You can link a computer later using the 'link' command.")

def main():
    parser = argparse.ArgumentParser(
        description="CraftOS-PC project management tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    
    parser.add_argument(
        'command',
        choices=['setup', 'link', 'unlink'],
        help='Command to execute'
    )
    
    parser.add_argument(
        'id',
        nargs='?',
        type=int,
        help='Computer ID (required for link/unlink commands)'
    )
    
    args = parser.parse_args()
    
    # Execute command
    if args.command == 'setup':
        setup_command()
    
    elif args.command == 'link':
        if args.id is None:
            parser.error("link command requires an ID argument")
        link_command(args.id)
    
    elif args.command == 'unlink':
        if args.id is None:
            parser.error("unlink command requires an ID argument")
        unlink_command(args.id)

if __name__ == '__main__':
    main()
