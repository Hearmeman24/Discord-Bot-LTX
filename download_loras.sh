#!/bin/bash
# Create log file
LOG_FILE="/tmp/lora_download.log"
echo "Starting LoRA downloads at $(date)" > $LOG_FILE

# Create directory if it doesn't exist
mkdir -p /models/loras
cd /models/loras || {
  echo "ERROR: Failed to cd to /models/loras directory" | tee -a $LOG_FILE
  exit 1
}

# Function to download a file with proper URL encoding
download_file() {
  filename="$1"
  # URL encode the filename for the URL
  encoded_url=$(echo "$filename" | sed -e "s/ /%20/g")
  echo "Downloading $filename..." | tee -a $LOG_FILE

  # Download with retries, showing progress, and logging
  wget -t 3 -O "$filename" "https://d1s3da0dcaf6kx.cloudfront.net/$encoded_url" 2>&1 | tee -a $LOG_FILE

  # Check status
  if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Successfully downloaded $filename" | tee -a $LOG_FILE
    # Verify file size
    filesize=$(stat -c%s "$filename")
    echo "   File size: $filesize bytes" | tee -a $LOG_FILE
    if [ "$filesize" -lt 1000 ]; then
      echo "   ⚠️ WARNING: File seems very small, might be corrupt or incomplete" | tee -a $LOG_FILE
    fi
    return 0
  else
    echo "❌ Failed to download $filename" | tee -a $LOG_FILE
    # Try to check if URL exists
    curl -s --head "https://d1s3da0dcaf6kx.cloudfront.net/$encoded_url" | head -n 1 | tee -a $LOG_FILE
    return 1
  fi
}

echo "=== Starting downloads at $(date) ===" | tee -a $LOG_FILE
echo "Download directory: $(pwd)" | tee -a $LOG_FILE

# Track success and failure
total_files=0
successful_downloads=0

# Download all LoRA files
file_list=(
  "wan-nsfw-e14-fixed.safetensors"
  "big_tits_epoch_50.safetensors"
  "pov_blowjob_v1.1.safetensors"
  "Wan_Breast_Helper_Hearmeman.safetensors"
  "wan_cowgirl_v1.3.safetensors"
  "cleavage_epoch_40.safetensors"
  "orgasm_e60.safetensors"
  "wan_missionary_side.safetensors"
  "dicks_epoch_100.safetensors"
  "masturbation_cumshot_wanI2V480p_v1.safetensors"
  "r0und4b0ut-wan-v1.0.safetensors"
  "facials_epoch_50.safetensors"
  "deepthroat_epoch_80.safetensors"
  "ahegao_v1_e35_wan.safetensors"
  "Wan_Pussy_LoRA_Hearmeman.safetensors"
  "doggyPOV_v1_1.safetensors"
  "wan_pov_missionary_v1.1.safetensors"
  "Titfuck_WAN14B_V1_Release.safetensors"
  "FILM_NOIR_EPOCH10.safetensors"
  "BouncyWalkV01.safetensors"
  "Spinning V2.safetensors"
  "squish_18.safetensors"
  "detailz-wan.safetensors"
  "studio_ghibli_wan14b_t2v_v01.safetensors"
  "Su_Bl_Ep02-Wan.safetensors"
  "wan_female_masturbation.safetensors"
  "Wan-Hip_Slammin_Assertive_Cowgirl.safetensors"
  "T2V - Skinny Petite Instagram Women - 14B.safetensors"
  "T2V-jiggle_tits-14b.safetensors"
)

# Process each file
for file in "${file_list[@]}"; do
  total_files=$((total_files+1))
  if download_file "$file"; then
    successful_downloads=$((successful_downloads+1))
  fi
  # Add a small delay between downloads
  sleep 1
done

# Summary
echo "=== Download Summary ===" | tee -a $LOG_FILE
echo "Total files: $total_files" | tee -a $LOG_FILE
echo "Successfully downloaded: $successful_downloads" | tee -a $LOG_FILE
echo "Failed downloads: $((total_files-successful_downloads))" | tee -a $LOG_FILE
echo "Completed at $(date)" | tee -a $LOG_FILE

# Check if all downloads were successful
if [ $successful_downloads -eq $total_files ]; then
  echo "✅ All LoRA files downloaded successfully" | tee -a $LOG_FILE
  exit 0
else
  echo "⚠️ Some LoRA files failed to download. Check $LOG_FILE for details" | tee -a $LOG_FILE
  # List files in directory
  echo "Files in directory:" | tee -a $LOG_FILE
  ls -la | tee -a $LOG_FILE
  exit 1
fi