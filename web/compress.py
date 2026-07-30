import os
from PIL import Image
import glob

# Input and output directories
input_dir = r"c:\Synchronization\web\Animation\450 frames of video"
output_dir = r"c:\Synchronization\web\assets\hero-frames"

os.makedirs(output_dir, exist_ok=True)

import re

image_files = glob.glob(os.path.join(input_dir, "*.[jJ][pP][gG]")) + \
              glob.glob(os.path.join(input_dir, "*.[pP][nN][gG]"))

# Extract numbers for natural sorting (so image_2 comes before image_10)
def natural_sort_key(s):
    return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s)]

image_files = sorted(image_files, key=natural_sort_key)

print(f"Found {len(image_files)} images to compress.")

for i, img_path in enumerate(image_files):
    try:
        with Image.open(img_path) as img:
            # Resize image proportionally to max width 1200px
            w, h = img.size
            if w > 1200:
                new_w = 1200
                new_h = int((new_w / w) * h)
                img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
                
            # Name files sequentially (frame_000.webp, frame_001.webp...)
            out_name = f"frame_{i:03d}.webp"
            out_path = os.path.join(output_dir, out_name)
            
            # Save as WebP with 50% quality and high compression effort (method=4)
            img.save(out_path, "WEBP", quality=50, method=4)
            
            if i % 50 == 0:
                print(f"Processed {i}/{len(image_files)}")
    except Exception as e:
        print(f"Error processing {img_path}: {e}")

print("Compression complete!")
