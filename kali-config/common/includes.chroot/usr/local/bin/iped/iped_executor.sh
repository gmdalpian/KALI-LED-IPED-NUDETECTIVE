#!/bin/bash
#
# iped_executor.sh
# "Engine" script for running IPED.
# (Native Arrays version for protection against spaces and complex paths)
#

export TEXTDOMAIN="iped_executor"
export TEXTDOMAINDIR="/usr/share/locale" # Adjust to your local path if testing

source /home/kali/forensic_utils.sh

# --- Constants ---
IPED_DIR="/usr/local/bin/iped"
# Base command separated in Array further below
OUTPUT_DIR_DESKTOP="/home/kali/Desktop/IPED-CASO"
OUTPUT_DIR_TRIAGE_BASE="/home/kali/Desktop/triage"
OUTPUT_DIR_TRIAGE_CASE="$OUTPUT_DIR_TRIAGE_BASE/IPED-CASO"
MEDIA_DIR="/run/media"
GPU_DETECT_SCRIPT="/usr/local/bin/gpu-detect.sh"

# --- Python Environment Variables (Venvs) ---
VENV_CUDA="/opt/venv-cuda/bin/activate"
VENV_CUDA_LEGACY="/opt/venv-cuda-legacy/bin/activate"
VENV_ROCM="/opt/venv-rocm/bin/activate"

# --- Global Variables ---
CONTINUE_PROCESSING=false
RECOVERED_CMD=""
COMMAND_LOG_FILE=""
LOG_FILE_PATH=""
FLAG_FILE=""
KALI_UID=1000
KALI_GID=1000
TARGET_ARRAY=() # Global array to store targets securely

# --- Logic Functions ---

# Function to handle BitLocker (Now uses Arrays)
handle_bitlocker() {
    local disk_device=$1
    local root_system=$2
    local disk_basename=$(basename "$disk_device")

    if [[ "$disk_basename" != *"$root_system"* ]]; then
        printf "$(gettext "Bitlocker detected on %s")\n" "$disk_device"
        sudo mkdir -p "/dislocker/bitlocker_$disk_basename"

        sudo dislocker -V "$disk_device" -- "/dislocker/bitlocker_$disk_basename" -r
        if sudo test -f "/dislocker/bitlocker_$disk_basename/dislocker-file"; then
            echo "$(gettext "Bitlocker (without password) mounted.")"
            sudo ln -sf "/dislocker/bitlocker_$disk_basename/dislocker-file" "/dislocker/dislocker-file_$disk_basename.dd"
            TARGET_ARRAY+=("-d" "/dislocker/dislocker-file_$disk_basename.dd")
        else
            while true; do
                BITLOCKER_INFO=('', '')
                while read -r line ; do
                    [[ $line =~ "Description:" ]] && BITLOCKER_INFO[0]=$line
                    [[ $line =~ "VMK protected with recovery passphrase" ]] && BITLOCKER_INFO[1]=${previousline^^}
                    previousline=$line
                done <<< "$(sudo cryptsetup bitlkDump "$disk_device")"

                zenity_title=$(gettext "BitLocker Detected!")
                zenity_text=$(printf "$(gettext $'Encrypted partition on %s.\nEnter the password or recovery key:\n\n%s\n%s')" "$disk_device" "${BITLOCKER_INFO[0]}" "${BITLOCKER_INFO[1]}")
                zenity_entry=$(gettext "RecoveryKey")

                bitlocker_pass=$(zenity --entry --title="$zenity_title" \
                    --text="$zenity_text" \
                    --entry-text "$zenity_entry" --width=500 2>/dev/null)

                if [ $? = 0 ]; then
                    sudo dislocker -V "$disk_device" -p"$bitlocker_pass" -- "/dislocker/bitlocker_$disk_basename" -r
                    if sudo test -f "/dislocker/bitlocker_$disk_basename/dislocker-file"; then
                        echo "$(gettext "Bitlocker decrypted with recovery key.")"
                        sudo ln -sf "/dislocker/bitlocker_$disk_basename/dislocker-file" "/dislocker/dislocker-file_$disk_basename.dd"
                        TARGET_ARRAY+=("-d" "/dislocker/dislocker-file_$disk_basename.dd")
                        break
                    else
                        sudo dislocker -V "$disk_device" --user-password="$bitlocker_pass" -- "/dislocker/bitlocker_$disk_basename" -r
                        if sudo test -f "/dislocker/bitlocker_$disk_basename/dislocker-file"; then
                            echo "$(gettext "Bitlocker decrypted with user password.")"
                            sudo ln -sf "/dislocker/bitlocker_$disk_basename/dislocker-file" "/dislocker/dislocker-file_$disk_basename.dd"
                            TARGET_ARRAY+=("-d" "/dislocker/dislocker-file_$disk_basename.dd")
                            break
                        else
                            zenity_err_title=$(gettext "BitLocker Key Error!")
                            zenity_err_text=$(gettext "The provided key or password did not decrypt the drive.")
                            zenity --error --title="$zenity_err_title" --text="$zenity_err_text" --width=300 --timeout=10 2>/dev/null
                        fi
                    fi
                else
                    echo "$(gettext "User canceled Bitlocker password insertion.")"
                    break
                fi
            done
        fi
    fi
}

# Logic to find and mount triage partition
setup_output_dir() {
    echo "$(gettext "Configuring output directory...")"
    
    local triage_part_device=$(get_triage_device)
    local TRIAGE_PARTITION_FOUND=false
    [ -n "$triage_part_device" ] && TRIAGE_PARTITION_FOUND=true

    if $TRIAGE_PARTITION_FOUND; then
        printf "$(gettext "Target device identified: %s")\n" "$triage_part_device"
        OUTPUT_DIR=$OUTPUT_DIR_TRIAGE_CASE
        DESKTOP_FILE="IPED-Caso-triage.desktop"
        
        if [ ! -d "$OUTPUT_DIR_TRIAGE_BASE" ]; then
             mkdir -p "$OUTPUT_DIR_TRIAGE_BASE"
        fi

        if findmnt --mountpoint $OUTPUT_DIR_TRIAGE_BASE &> /dev/null; then
             echo "$(gettext "Triage partition is already mounted.")"
             if [ "$(stat -c '%u' "$OUTPUT_DIR_TRIAGE_BASE")" != "$KALI_UID" ]; then
                  sudo umount "$OUTPUT_DIR_TRIAGE_BASE" &> /dev/null
                  if ! sudo mount -o rw,uid=$KALI_UID,gid=$KALI_GID $triage_part_device $OUTPUT_DIR_TRIAGE_BASE; then
                       TRIAGE_PARTITION_FOUND=false
                       OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
                       DESKTOP_FILE="IPED-Caso.desktop"
                  fi
             fi
        else
            if ! sudo mount -o rw,uid=$KALI_UID,gid=$KALI_GID $triage_part_device $OUTPUT_DIR_TRIAGE_BASE; then
                TRIAGE_PARTITION_FOUND=false
                OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
                DESKTOP_FILE="IPED-Caso.desktop"
            fi
        fi

        if $TRIAGE_PARTITION_FOUND; then
            if test -f "$OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"; then
                KEYWORD_FILE_PATH="$OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"
            else
                KEYWORD_FILE_PATH="$IPED_DIR/palavras-chave.txt"
            fi
            
            sudo cp "$IPED_DIR/LocalConfig-triage.txt" "$IPED_DIR/LocalConfig.txt"

            # --- START OF THREAD/RAM BALANCING LOGIC ---
            local total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
            local total_mem_mb=$((total_mem_kb / 1024))
            local max_threads=$((total_mem_mb / 1024))
            
            if [ "$max_threads" -lt 2 ]; then max_threads=2; fi
            local cpu_cores=$(nproc)
            
            if [ "$cpu_cores" -gt "$max_threads" ]; then
                printf "$(gettext "WARNING: Low memory per core detected (Cores: %s, RAM: %sMB).")\n" "$cpu_cores" "$total_mem_mb"
                printf "$(gettext "Adjusting numThreads from 'default' to '%s' in LocalConfig.txt.")\n" "$max_threads"
                sudo sed -i "s/^numThreads = default/numThreads = $max_threads/" "$IPED_DIR/LocalConfig.txt"
            else
                printf "$(gettext "Sufficient memory detected (Cores: %s, RAM: %sMB). Keeping numThreads = default.")\n" "$cpu_cores" "$total_mem_mb"
            fi

            # --- SWAP Logic ---
            if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
                if [ "$(cat /proc/swaps | wc -l)" -le 1 ]; then
                    local swap_file_path="$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                    if test -f "$swap_file_path"; then
                         sudo swapon "$swap_file_path"
                         if [ $? -ne 0 ]; then
                             sudo swapoff "$swap_file_path" &> /dev/null
                             rm -f "$swap_file_path"
                         else
                              local create_swap=false
                         fi
                    fi

                    if [ ! -f "$swap_file_path" ] || [ "$create_swap" != "false" ]; then
                         available_kb=$(df -k "$OUTPUT_DIR_TRIAGE_BASE" | tail -n 1 | awk '{print $4}')
                         available_kb=${available_kb:-0}

                         if (( available_kb > 102400 )); then
                              target_kb=$((available_kb / 10))
                              max_kb=$((10 * 1024 * 1024))
                              (( target_kb > max_kb )) && swap_size_kb=$max_kb || swap_size_kb=$target_kb
                              swap_size_mb=$((swap_size_kb / 1024))

                              if truncate -s "${swap_size_mb}M" "$swap_file_path"; then
                                   sudo mkswap "$swap_file_path"
                                   sudo swapon "$swap_file_path" || rm -f "$swap_file_path"
                              fi
                         fi
                    fi
                fi
            fi 
        fi 
    else 
        echo "$(gettext "No IPED-TRIAGE partition found. Using Desktop.")"
        OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
        DESKTOP_FILE="IPED-Caso.desktop"
        KEYWORD_FILE_PATH="$IPED_DIR/palavras-chave.txt"
		
        if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
            printf "$(gettext "WARNING: Profile '%s' without Triage partition may cause out of memory.")\n" "$PROFILE"
            
            zenity_warn_title=$(gettext "Triage Partition Not Found")
            zenity_warn_text=$(printf "$(gettext $'For profile \'%s\', it is highly recommended to use an \'IPED-TRIAGE\' partition to store the case and create a SWAP file.\n\nContinuing may cause instability or lack of memory.')" "$PROFILE")
            zenity --warning --title="$zenity_warn_title" --text="$zenity_warn_text" --width=400 2>/dev/null
        fi		
    fi

    # --- CENTRALIZED LOG AND FLAG PATHS ---
    COMMAND_LOG_FILE="$OUTPUT_DIR/iped_comando_executado.log"
    LOG_FILE_PATH="$OUTPUT_DIR/IPED-Processamento-$(date +%y%m%d%H%M).log"
    FLAG_FILE="$OUTPUT_DIR/.processing_incomplete"

    # --- MULTI-CASE & RESUME LOGIC MATRIX ---
    if [ -d "$OUTPUT_DIR" ]; then
        if [ -f "$FLAG_FILE" ]; then
            # SCENARIO A: INCOMPLETE CASE (Flag Exists)
            zenity_q_title=$(gettext "Incomplete Case Detected")
            zenity_q_text=$(printf "$(gettext $'An interrupted case was found at:\n<b>%s</b>\n\nWhat do you want to do?')" "$OUTPUT_DIR")

            USER_CHOICE=$(zenity --list --radiolist \
                --title="$zenity_q_title" \
                --text="$zenity_q_text" \
                --column="$(gettext 'Select')" --column="ID" --column="$(gettext 'Action')" \
                --hide-column=2 --print-column=2 \
                TRUE "1" "$(gettext 'Continue previous processing')" \
                FALSE "2" "$(gettext 'Delete case and start a new one')" \
                --width=450 --height=220 2>/dev/null)

            if [ $? -ne 0 ] || [ -z "$USER_CHOICE" ]; then exit 0; fi

            if [ "$USER_CHOICE" == "1" ]; then
                CONTINUE_PROCESSING=true
                if [ -f "$COMMAND_LOG_FILE" ]; then
                     local escaped_output_dir=$(sed 's#[&/\]#\\&#g' <<<"$OUTPUT_DIR")
                     local original_cmd=$(grep "$escaped_output_dir" "$COMMAND_LOG_FILE" | tail -n 1 | sed -E 's/^\[[^]]+\] [^:]+: //')
                     
                     if [ -z "$original_cmd" ]; then exit 7; fi
                     local original_profile=$(echo "$original_cmd" | grep -o '\-profile [^ ]*' | awk '{print $2}' | tr -d "'\"")
                     PROFILE=$original_profile

                     if echo "$original_cmd" | grep -q -- "-jar iped.jar"; then
                         if ! echo "$original_cmd" | grep -q -- '--continue'; then
                              RECOVERED_CMD=$(echo "$original_cmd" | sed 's/-jar iped\.jar/-jar iped.jar --continue/')
                         else
                              RECOVERED_CMD="$original_cmd"
                         fi
                     else
                         exit 9
                     fi
                else
                     zenity --error --text="$(gettext 'Command log not found. Cannot continue.')"
                     exit 7
                fi
            else
                # Delete interrupted case
                sudo rm -rf "$OUTPUT_DIR"
                sudo mkdir -p "$OUTPUT_DIR"
                sudo chown $KALI_UID:$KALI_GID "$OUTPUT_DIR"
                CONTINUE_PROCESSING=false
            fi
        else
            # SCENARIO B: COMPLETED CASE (No Flag)
            zenity_q_title=$(gettext "Existing Case")
            zenity_q_text=$(printf "$(gettext $'A completed case already exists at:\n<b>%s</b>\n\nWhat do you want to do?')" "$OUTPUT_DIR")

            USER_CHOICE=$(zenity --list --radiolist \
                --title="$zenity_q_title" \
                --text="$zenity_q_text" \
                --column="$(gettext 'Select')" --column="ID" --column="$(gettext 'Action')" \
                --hide-column=2 --print-column=2 \
                FALSE "1" "$(gettext 'Delete previous case and process a new one')" \
                TRUE "2" "$(gettext 'Archive previous case and process a new one')" \
                --width=450 --height=220 2>/dev/null)

            if [ $? -ne 0 ] || [ -z "$USER_CHOICE" ]; then exit 0; fi

            if [ "$USER_CHOICE" == "2" ]; then
                local counter=1
                local counter_str
                local new_dir_name
                
                while true; do
                    counter_str=$(printf "%02d" "$counter")
                    new_dir_name="${OUTPUT_DIR}-${counter_str}"
                    if [ ! -d "$new_dir_name" ]; then break; fi
                    ((counter++))
                done

                echo "$(gettext 'Archiving previous case to:') $new_dir_name"
                sudo mv "$OUTPUT_DIR" "$new_dir_name"

                local desk_shortcut="/home/kali/Desktop/IPED-Caso.desktop"
                local new_desk_shortcut="/home/kali/Desktop/IPED-Caso-${counter_str}.desktop"

                if [ -f "$desk_shortcut" ]; then
                    sudo mv "$desk_shortcut" "$new_desk_shortcut"
                    sudo sed -i "s|${OUTPUT_DIR}|${new_dir_name}|g" "$new_desk_shortcut"
                    sudo sed -i "s|^Name=.*|&-${counter_str}|" "$new_desk_shortcut"
                    sudo sed -i "s|^Name\[.*\]=.*|&-${counter_str}|" "$new_desk_shortcut"
                fi
            else
                sudo rm -rf "$OUTPUT_DIR"
            fi

            sudo mkdir -p "$OUTPUT_DIR"
            sudo chown $KALI_UID:$KALI_GID "$OUTPUT_DIR"
            CONTINUE_PROCESSING=false
        fi
    else
        # SCENARIO C: FRESH START (Directory does not exist)
        sudo mkdir -p "$OUTPUT_DIR"
        sudo chown $KALI_UID:$KALI_GID "$OUTPUT_DIR"
        CONTINUE_PROCESSING=false
    fi
}

# --- UPDATE: Builds the targets array using forensic_utils.sh ---
build_targets() {
    TARGET_ARRAY=()
    local root_system=$(get_boot_disk_name)

    case $TARGET_MODE in
        "all_disks")
            echo "$(gettext "Building targets: Disks")"

            # 1. Physical Disks
            while read -r line ; do
                local disk=$(echo "$line" | awk '{print $1}')
                if [[ "$disk" != "$root_system" ]]; then
                    TARGET_ARRAY+=("-d" "/dev/$disk")
                fi
            done <<< "$(lsblk -lno NAME,TYPE | grep disk)"

            # 2. LDM (Windows RAID)
            sudo ldmtool create all &> /dev/null
            sudo udevadm settle
            while read -r disk; do
                if [[ -n "$disk" ]]; then
                    TARGET_ARRAY+=("-d" "/dev/mapper/$disk")
                fi
            done <<< "$(lsblk -lno NAME --filter "TYPE == 'ldm'")"

            # 3. VSS
            if [ -d "/vss" ]; then
                sudo mkdir -p /vss_iped
                while read -r line ; do
                    for vss in $(sudo ls /vss/$line 2>/dev/null); do
                        sudo ln -sf "/vss/$line/$vss" "/vss_iped/$line-$vss.dd"
                        TARGET_ARRAY+=("-d" "/vss_iped/$line-$vss.dd")
                    done
                done <<< "$(sudo ls /vss/ 2>/dev/null)"
            fi

            # 4. BitLocker
            sudo mkdir -p /dislocker
            while read -r line ; do
                if [ ! -z "$line" ]; then
                    handle_bitlocker "$line" "$root_system"
                fi
            done <<< "$(sudo dislocker-find)"
            ;;

        "mounted_files")
            echo "$(gettext "Building targets: Mounted Files")"
            if [ -f "/home/kali/mount_disks.sh" ]; then
                /home/kali/mount_disks.sh
            fi
            TARGET_ARRAY+=("-d" "$MEDIA_DIR")
            ;;

        "manual_dir")
            echo "$(gettext "Building targets: Manual Selection")"
            if [ -z "$MANUAL_PATH" ]; then exit 5; fi
            # The Array accepts spaces normally
            TARGET_ARRAY+=("-d" "$MANUAL_PATH")
            ;;
    esac

    if [ ${#TARGET_ARRAY[@]} -eq 0 ]; then
        zenity_tgt_err=$(gettext "No processing target was determined.")
        zenity --error --text="$zenity_tgt_err" 2>/dev/null
        exit 3
    fi
}

run_post_processing() {
    echo "$(gettext "Starting post-processing...")"
    cp "$IPED_DIR/Ferramenta_de_Pesquisa.sh" "$OUTPUT_DIR/"
    cp "$IPED_DIR/$DESKTOP_FILE" "/home/kali/Desktop/IPED-Caso.desktop"
    sudo chown kali:kali "/home/kali/Desktop/IPED-Caso.desktop" || true
    
    cd "$OUTPUT_DIR"
    if [ -f "./Ferramenta_de_Pesquisa.sh" ]; then
        ./Ferramenta_de_Pesquisa.sh
    fi
}

# --- Main Function ---

if [ $# -eq 0 ]; then exit 1; fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile) SELECTED_PROFILE="$2"; shift ;;
        --target) TARGET_MODE="$2"; shift ;;
        --path) MANUAL_PATH="$2"; shift ;;
        *) printf "$(gettext "Unknown parameter: %s")\n" "$1"; exit 1 ;;
    esac
    shift
done
PROFILE=$SELECTED_PROFILE

cd "$IPED_DIR" || exit 1
sudo mplayer &> /dev/null

setup_output_dir

if ! $CONTINUE_PROCESSING; then
     build_targets 
fi

# =========================================================
# GPU DETECTION AND PYTHON ENVIRONMENT SELECTION
# =========================================================
PYTHON_TARGET=""
if [ -f "$GPU_DETECT_SCRIPT" ] && ! grep -q "nonvidia" /proc/cmdline; then
    eval $($GPU_DETECT_SCRIPT) 
    
    CANDIDATO=""
    if [ "$VENDOR" = "NVIDIA" ]; then
        if [ "$DRIVER" = "open" ]; then
            CANDIDATO="$VENV_CUDA"
        elif [ "$DRIVER" = "legacy" ]; then
            CANDIDATO="$VENV_CUDA_LEGACY"
        fi
    elif [ "$VENDOR" = "AMD" ] && [ "$DRIVER" != "none" ]; then
        # Only enters here if it is a discrete AMD GPU (e.g., RX 6000+)
        CANDIDATO="$VENV_ROCM"
    fi

    # Validates if the environment path exists
    if [ -n "$CANDIDATO" ] && [ -f "$CANDIDATO" ]; then
        PYTHON_TARGET="$CANDIDATO"
        printf "$(gettext "Hardware Detected: %s (%s) - Driver: %s")\n" "$VENDOR" "$ARCH" "$DRIVER"
        printf "$(gettext "Active Environment: %s")\n" "$PYTHON_TARGET"
    else
        printf "$(gettext "CPU Mode: Detected hardware (%s %s) does not support stable acceleration.")\n" "$VENDOR" "$ARCH"
    fi
fi
# =========================================================
    
# =========================================================
# 4. Secure Command Construction (ARRAYS + POSITIONAL)
# =========================================================
if $CONTINUE_PROCESSING; then
    FINAL_CMD=$RECOVERED_CMD
    echo "========================================================"
    printf "$(gettext "COMMAND TO CONTINUE (Original Profile '%s'):")\n" "$PROFILE"
    echo "$FINAL_CMD"
    echo "========================================================"
    
    # 5. Execution Continuation
    eval "$FINAL_CMD"
    
    if [ $? -ne 0 ]; then
        zenity_cont_err=$(printf "$(gettext $'An error occurred while continuing IPED processing.\nCheck the log in this terminal or at %s')" "$LOG_FILE_PATH")
        zenity --error --text="$zenity_cont_err" --width=500 2>/dev/null
        exit 4
    fi
else
    # Creates the command base as an Array
    IPED_CMD=("java" "--module-path" "/usr/share/openjfx/lib/" "--add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base" "-jar" "iped.jar" "-o" "$OUTPUT_DIR" "-profile" "$PROFILE")
    
    if [ -n "$LOG_FILE_PATH" ]; then
        IPED_CMD+=("-log" "$LOG_FILE_PATH")
    fi
    if [ -n "$KEYWORD_FILE_PATH" ]; then
        IPED_CMD+=("-l" "$KEYWORD_FILE_PATH")
    fi
    
    # Appends the targets array (natively immune to spaces)
    IPED_CMD+=("${TARGET_ARRAY[@]}")

    # Creates a readable string for the LOG and for future continuation
    SAFE_ARGS=$(printf "%q " "${IPED_CMD[@]}")
    
    if [ -n "$PYTHON_TARGET" ]; then
        # THE TRICK: We pass the logic in bash -c, but the data comes OUTSIDE the quotes.
        # The '--' becomes $0, PYTHON_TARGET becomes $1 and the rest becomes $@
        LOG_CMD="sudo bash -c 'source \"\$1\"; shift; exec \"\$@\"' -- $(printf "%q" "$PYTHON_TARGET") $SAFE_ARGS"
    else
        LOG_CMD="sudo $SAFE_ARGS"
    fi

    echo "========================================================"
    echo "$(gettext "FINAL COMMAND TO BE EXECUTED:")"
    echo "$LOG_CMD"
    echo "========================================================"
	
    # --- IPED LOCALIZATION (LANGUAGE) LOGIC ---
    # Defines the IPED locale based on the system language ($LANG)
    # Supported by IPED: 'en', 'pt-BR', 'it-IT', 'de-DE', 'es-AR' & 'fr-FR'
    IPED_LOCALE="en"
    if [[ "$LANG" == pt_BR* || "$LANG" == pt_PT* ]]; then
        IPED_LOCALE="pt-BR"
    elif [[ "$LANG" == it_IT* ]]; then
        IPED_LOCALE="it-IT"
    elif [[ "$LANG" == de_DE* ]]; then
        IPED_LOCALE="de-DE"
    elif [[ "$LANG" == es_AR* || "$LANG" == es_ES* || "$LANG" == es_* ]]; then
        IPED_LOCALE="es-AR"
    elif [[ "$LANG" == fr_FR* || "$LANG" == fr_* ]]; then
        IPED_LOCALE="fr-FR"
    fi

    printf "$(gettext "Configuring IPED locale to: %s")\n" "$IPED_LOCALE"
    
    # Replaces the line, even if commented, or appends to the end of the file
    if grep -q "^[#]*[[:space:]]*locale[[:space:]]*=" "$IPED_DIR/LocalConfig.txt"; then
        sudo sed -i "s/^[#]*[[:space:]]*locale[[:space:]]*=.*/locale = $IPED_LOCALE/" "$IPED_DIR/LocalConfig.txt"
    else
        echo "locale = $IPED_LOCALE" | sudo tee -a "$IPED_DIR/LocalConfig.txt" > /dev/null
    fi
    # ------------------------------------------	

# COMMAND LOG
    printf "$(gettext "Registering command in %s...")\n" "$COMMAND_LOG_FILE"
    mkdir -p "$(dirname "$COMMAND_LOG_FILE")"
    printf "$(gettext "[%s] Executing: %s")\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_CMD" >> "$COMMAND_LOG_FILE"
    chown kali:kali "$COMMAND_LOG_FILE" || echo "$(gettext "Warning: Failed to change log file owner.")"

    # CREATE CONTROL FLAG
    touch "$FLAG_FILE"
    chown kali:kali "$FLAG_FILE" 2>/dev/null

    echo "$(gettext "Starting IPED... This may take a long time.")"

    # =========================================================
    # 5. Main Execution (THE MAGIC HAPPENS HERE)
    # =========================================================
    if [ -n "$PYTHON_TARGET" ]; then
        # We execute by injecting the array natively. No "eval", therefore no escaping error!
        sudo bash -c 'source "$1"; shift; exec "$@"' -- "$PYTHON_TARGET" "${IPED_CMD[@]}"
    else
        sudo "${IPED_CMD[@]}"
    fi

    if [ $? -ne 0 ]; then
        echo "$(gettext "ERROR: IPED processing failed.")"
        zenity_main_err=$(printf "$(gettext $'An error occurred during IPED processing.\nCheck the log in this terminal or at %s\n\nYou can try running again and choose \'Continue previous processing\'.')" "$LOG_FILE_PATH")
        zenity --error --text="$zenity_main_err" --width=500 2>/dev/null
        exit 4
    fi

fi

# PROCESSING COMPLETED SUCCESSFULLY: REMOVE FLAG
rm -f "$FLAG_FILE"
		
echo "$(gettext "IPED processing finished successfully.")"
echo "---------------------------------------------"

# 6. Post-Processing
run_post_processing
echo "$(gettext "Post-processing completed.")"

printf "$(gettext "Case available at: %s")\n" "$OUTPUT_DIR"
echo "============================================="