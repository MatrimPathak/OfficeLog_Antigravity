import os
from PIL import Image, ImageDraw

# Configuration
SOURCE_IMAGE_PATH = 'Logo_Source.png' # Assumes script is run from project root
ANDROID_RES_DIR = 'android/app/src/main/res'
IOS_ASSETS_DIR = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
IOS_ICONS_DIR = 'ios/Runner/Icons' # For alternate icons

COLORS = {
    'primary': '#2E88F6',
}

ANDROID_SIZES = [
    ('mipmap-mdpi', 48),
    ('mipmap-hdpi', 72),
    ('mipmap-xhdpi', 96),
    ('mipmap-xxhdpi', 144),
    ('mipmap-xxxhdpi', 192),
]

IOS_SIZES = [
    # (size, scale, filename)
    (20, 1, 'Icon-App-20x20@1x.png'),
    (20, 2, 'Icon-App-20x20@2x.png'),
    (20, 3, 'Icon-App-20x20@3x.png'),
    (29, 1, 'Icon-App-29x29@1x.png'),
    (29, 2, 'Icon-App-29x29@2x.png'),
    (29, 3, 'Icon-App-29x29@3x.png'),
    (40, 1, 'Icon-App-40x40@1x.png'),
    (40, 2, 'Icon-App-40x40@2x.png'),
    (40, 3, 'Icon-App-40x40@3x.png'),
    (60, 2, 'Icon-App-60x60@2x.png'),
    (60, 3, 'Icon-App-60x60@3x.png'),
    (76, 1, 'Icon-App-76x76@1x.png'),
    (76, 2, 'Icon-App-76x76@2x.png'),
    (83.5, 2, 'Icon-App-83.5x83.5@2x.png'),
    (1024, 1, 'Icon-App-1024x1024@1x.png'),
]

def create_icon_variant(source_img, bg_color, size, remove_alpha=False):
    """Creates a standardized icon with the given background color and size."""
    # Create background
    icon = Image.new('RGBA', (size, size), bg_color)
    
    # Calculate source image size
    padding_ratio = 0.05
    target_source_size = int(size * (1 - 2 * padding_ratio))
    
    # Resize source image maintaining aspect ratio
    aspect = source_img.size[0] / source_img.size[1]
    if aspect > 1:
        new_w = target_source_size
        new_h = int(target_source_size / aspect)
    else:
        new_h = target_source_size
        new_w = int(target_source_size * aspect)
        
    resized_source = source_img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    # Center the source image on the background
    x = (size - new_w) // 2
    y = (size - new_h) // 2
    
    icon.paste(resized_source, (x, y), resized_source)
    
    if remove_alpha:
        return icon.convert('RGB')
    return icon

def generate_android_icons(source_img):
    print("Generating Android icons...")
    color_hex = COLORS['primary']
    base_name = 'ic_launcher' 
            
    for folder, size in ANDROID_SIZES:
        out_dir = os.path.join(ANDROID_RES_DIR, folder)
        os.makedirs(out_dir, exist_ok=True)
        
        icon = create_icon_variant(source_img, color_hex, size)
        
        # Save main icon
        icon.save(os.path.join(out_dir, f'{base_name}.png'))
        icon.save(os.path.join(out_dir, f'{base_name}_round.png'))

        # Generate Foreground for Adaptive Icon
        foreground_size = int(size * (108/48))
        foreground = Image.new('RGBA', (foreground_size, foreground_size), (0, 0, 0, 0))
        
        fg_padding_ratio = 0.25 
        target_fg_size = int(foreground_size * (1 - 2 * fg_padding_ratio))
        
        # Resize source
        aspect = source_img.size[0] / source_img.size[1]
        if aspect > 1:
            new_w = target_fg_size
            new_h = int(target_fg_size / aspect)
        else:
            new_h = target_fg_size
            new_w = int(target_fg_size * aspect)
            
        resized_source = source_img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        
        x = (foreground_size - new_w) // 2
        y = (foreground_size - new_h) // 2
        
        foreground.paste(resized_source, (x, y), resized_source)
        foreground.save(os.path.join(out_dir, 'ic_launcher_foreground.png'))

    # Generate Adaptive Icon XMLs
    anydpi_dir = os.path.join(ANDROID_RES_DIR, 'mipmap-anydpi-v26')
    os.makedirs(anydpi_dir, exist_ok=True)
    
    # Main Icon
    with open(os.path.join(anydpi_dir, 'ic_launcher.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/primary_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

    with open(os.path.join(anydpi_dir, 'ic_launcher_round.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/primary_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

def generate_ios_icons(source_img):
    print("Generating iOS icons...")
    
    # Ensure directories exist
    os.makedirs(IOS_ASSETS_DIR, exist_ok=True)
    
    # 1. Generate Primary (Default) Icons in Assets.xcassets
    for size_pt, scale, filename in IOS_SIZES:
        pixel_size = int(size_pt * scale)
        icon = create_icon_variant(source_img, COLORS['primary'], pixel_size, remove_alpha=True)
        icon.save(os.path.join(IOS_ASSETS_DIR, filename))

def main():
    if not os.path.exists(SOURCE_IMAGE_PATH):
        print(f"Error: {SOURCE_IMAGE_PATH} not found.")
        return

    try:
        source_img = Image.open(SOURCE_IMAGE_PATH).convert("RGBA")
    except Exception as e:
        print(f"Error opening image: {e}")
        return

    generate_android_icons(source_img)
    generate_ios_icons(source_img)
    print("Icon generation complete.")

if __name__ == '__main__':
    main()
