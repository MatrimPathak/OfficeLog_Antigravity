import os
from PIL import Image, ImageDraw

# Configuration
SOURCE_IMAGE_PATH = 'Logo_Source.png' # Assumes script is run from project root
ANDROID_RES_DIR = 'android/app/src/main/res'
IOS_ASSETS_DIR = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
IOS_ICONS_DIR = 'ios/Runner/Icons' # For alternate icons

COLORS = {
    'primary': '#2E88F6',
    'danger': '#FF5959',
    'warning': '#FF9F43',
    'success': '#4CAF50',
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
    (20, 2, 'Icon-App-20x20@2x.png'),
    (20, 3, 'Icon-App-20x20@3x.png'),
    (29, 2, 'Icon-App-29x29@2x.png'),
    (29, 3, 'Icon-App-29x29@3x.png'),
    (40, 2, 'Icon-App-40x40@2x.png'),
    (40, 3, 'Icon-App-40x40@3x.png'),
    (60, 2, 'Icon-App-60x60@2x.png'),
    (60, 3, 'Icon-App-60x60@3x.png'),
    (1024, 1, 'Icon-App-1024x1024.png'),
]

def create_icon_variant(source_img, bg_color, size):
    """Creates a standardized icon with the given background color and size."""
    # Create background
    icon = Image.new('RGBA', (size, size), bg_color)
    
    # Calculate source image size (e.g., 100% of icon size)
    # The source image should be transparent PNG with the white logo
    padding_ratio = 0.05
    target_source_size = int(size * (1 - 2 * padding_ratio))
    
    # Resize source image maintaining aspect ratio
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
    return icon

def generate_android_icons(source_img):
    print("Generating Android icons...")
    for name, color_hex in COLORS.items():
        base_name = 'ic_launcher' 
        if name != 'primary':
            base_name += f'_{name}'
            
        for folder, size in ANDROID_SIZES:
            out_dir = os.path.join(ANDROID_RES_DIR, folder)
            os.makedirs(out_dir, exist_ok=True)
            
            icon = create_icon_variant(source_img, color_hex, size)
            
            # Save main icon
            icon.save(os.path.join(out_dir, f'{base_name}.png'))
            # Save round icon (Android often expects this too, though adaptive icons are standard now)
            icon.save(os.path.join(out_dir, f'{base_name}_round.png'))

            # Generate Foreground for Adaptive Icon
            # Adaptive icon foreground is 108dp.
            # mdpi 1dp=1px -> 108px.
            # The current loop 'size' is the legacy icon size (e.g. 48px for mdpi).
            # We need to map legacy size to foreground size.
            # mdpi (48) -> 108
            # hdpi (72) -> 162
            # xhdpi (96) -> 216
            # xxhdpi (144) -> 324
            # xxxhdpi (192) -> 432
            
            foreground_size = int(size * (108/48))
            
            # Create a transparent image for foreground
            foreground = Image.new('RGBA', (foreground_size, foreground_size), (0, 0, 0, 0))
            
            # The logo (source_img) needs to be resized to fit within the safe zone (66dp = 66/108 = 0.61)
            # Or better, let's just center it.
            # User wanted it to fill 100% of the legacy icon.
            # For adaptive icon, the safe zone is circle of diameter 66dp.
            # Background is 108x108.
            # If we place the logo at full 108x108, it will be clipped.
            # Safe zone is roughly 61% of the full image.
            # Let's make the logo filling the safe zone + a bit more?
            # User said "white peaks from behind", they want the blue to obscure everything.
            # Background layer handles the blue.
            # Foreground layer handles the logo.
            # We should resize "Logo_Source.png" to fit nicely within the 66dp/72dp viewport.
            # Let's use 60% of 108dp = ~65dp.
            
            fg_padding_ratio = 0.25 # Adjust to keep logo within safe area
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
    
    # 1. Main Icon (Primary)
    with open(os.path.join(anydpi_dir, 'ic_launcher.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/primary_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

    # 1.1 Round Icon (Primary)
    with open(os.path.join(anydpi_dir, 'ic_launcher_round.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/primary_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

    # 2. Danger Icon
    with open(os.path.join(anydpi_dir, 'ic_launcher_danger.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/danger_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')
    
    # 2.1 Danger Round
    with open(os.path.join(anydpi_dir, 'ic_launcher_danger_round.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/danger_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

    # 3. Warning Icon
    with open(os.path.join(anydpi_dir, 'ic_launcher_warning.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/warning_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

    # 3.1 Warning Round
    with open(os.path.join(anydpi_dir, 'ic_launcher_warning_round.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/warning_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

    # 4. Success Icon
    with open(os.path.join(anydpi_dir, 'ic_launcher_success.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/success_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')

    # 4.1 Success Round
    with open(os.path.join(anydpi_dir, 'ic_launcher_success_round.xml'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/success_color"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>''')


def generate_ios_icons(source_img):
    print("Generating iOS icons...")
    
    # Ensure directories exist
    os.makedirs(IOS_ASSETS_DIR, exist_ok=True)
    os.makedirs(IOS_ICONS_DIR, exist_ok=True)
    
    # 1. Generate Primary (Default) Icons in Assets.xcassets
    for size_pt, scale, filename in IOS_SIZES:
        pixel_size = size_pt * scale
        icon = create_icon_variant(source_img, COLORS['primary'], pixel_size)
        icon.save(os.path.join(IOS_ASSETS_DIR, filename))

    # 2. Generate Alternate Icons (Danger, Warning, Success) in generic directory
    # iOS alternate icons are usually just the 60pt@2x (120x120) and 60pt@3x (180x180) and 1024?
    # Actually, we need to define them in Info.plist.
    # We will generate a set of common sizes for alternates.
    
    alternate_sizes = [
        (60, 2, '@2x'),
        (60, 3, '@3x'),
        (76, 2, '~ipad@2x'), # iPad App
        (83.5, 2, '~ipad@2x'), # iPad Pro
        (1024, 1, '_1024'), # App Store
    ]

    for name, color_hex in COLORS.items():
        if name == 'primary': continue # Already done in Assets
        
        for size_pt, scale, suffix in alternate_sizes:
            pixel_size = int(size_pt * scale) # 83.5 becomes 167
            icon = create_icon_variant(source_img, color_hex, pixel_size)
            # Naming convention: icon_danger@2x.png
            filename = f'icon_{name}{suffix}.png'.replace('~', '_') # Sanitize ~ for filename if needed? 
            # Actually standard convention often uses ~ for ipad but let's stick to simple names referenced in Info.plist
            
            # We will use simple filenames and reference them in Info.plist
            # e.g. "danger", "warning", "success"
            # iOS looks for filenames based on the key in plist
            
            # Let's just generate high res versions that iOS can downscale if needed, 
            # but ideally we provide specific sizes. 
            # For `flutter_dynamic_icon`, we usually just put the files in ios/Runner/Icons
            
            # Generating just the 120 and 180 and 1024 is usually enough for iPhone
            pass
            
        # Simplified IOS Alternate Generation:
        # We'll generate a 120x120, 180x180, and 1024x1024 for each variant
        # And save them as [name] uses default @2x, @3x lookup
        
        # 120x120
        icon120 = create_icon_variant(source_img, color_hex, 120)
        icon120.save(os.path.join(IOS_ICONS_DIR, f'{name}@2x.png'))
        
        # 180x180
        icon180 = create_icon_variant(source_img, color_hex, 180)
        icon180.save(os.path.join(IOS_ICONS_DIR, f'{name}@3x.png'))
        
        # 1024x1024
        icon1024 = create_icon_variant(source_img, color_hex, 1024)
        icon1024.save(os.path.join(IOS_ICONS_DIR, f'{name}_1024.png'))

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
