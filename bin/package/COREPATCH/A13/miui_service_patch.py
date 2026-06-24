import os
import re
import logging
import glob

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')


def modify_file(file_path, search_pattern, add_line_template):
    logging.info(f"Modifying file: {file_path}")
    with open(file_path, 'r', encoding="utf-8") as file:
        lines = file.readlines()

    modified_lines = []
    for line in lines:
        modified_lines.append(line)
        match = re.search(search_pattern, line)
        if match:
            vX = match.group(1)
            add_line = add_line_template.format(vX=vX)
            logging.info(f"Found pattern in file: {file_path} with variable {vX}")
            modified_lines.append(add_line + '\n')

    with open(file_path, 'w', encoding="utf-8") as file:
        file.writelines(modified_lines)
    logging.info(f"Completed modification for file: {file_path}")


def replace_string_in_file(file_path, search_string, replace_string):
    logging.info(f"Replacing string in file: {file_path}")
    with open(file_path, 'r', encoding="utf-8") as file:
        content = file.read()

    modified_content = content.replace(search_string, replace_string)

    with open(file_path, 'w', encoding="utf-8") as file:
        file.write(modified_content)
    logging.info(f"Completed string replacement in file: {file_path}")


def modify_not_allow_capture_display(file_path):
    logging.info(f"Modifying notAllowCaptureDisplay method in file: {file_path}")
    with open(file_path, 'r', encoding="utf-8") as file:
        lines = file.readlines()

    modified_lines = []
    in_method = False
    method_start_line = ""
    search_pattern = re.compile(
        r'\.method public notAllowCaptureDisplay\(Lcom/android/server/wm/RootWindowContainer;I\)Z'
    )

    for line in lines:
        if in_method:
            if line.strip() == '.end method':
                modified_lines.append(method_start_line)
                modified_lines.append("    .registers 2\n")
                modified_lines.append("    const/4 v0, 0x0\n")
                modified_lines.append("    return v0\n")
                modified_lines.append(line)
                in_method = False
                method_start_line = ""
            # skip old body
        elif search_pattern.search(line):
            in_method = True
            method_start_line = line
        else:
            modified_lines.append(line)

    with open(file_path, 'w', encoding="utf-8") as file:
        file.writelines(modified_lines)
    logging.info(f"Completed modification for notAllowCaptureDisplay method in file: {file_path}")


def modify_checksysappcrack(file_path):
    logging.info(f"Modifying checkSysAppCrack method in file: {file_path}")
    with open(file_path, 'r', encoding="utf-8") as file:
        lines = file.readlines()

    modified_lines = []
    in_method = False
    method_start_line = ""
    search_pattern = re.compile(r'\.method.*checkSysAppCrack\(\)Z')

    for line in lines:
        if in_method:
            if line.strip() == '.end method':
                modified_lines.append(method_start_line)
                modified_lines.append("    .registers 10\n")
                modified_lines.append("    const/4 v0, 0x1\n")
                modified_lines.append("    return v0\n")
                modified_lines.append(line)
                in_method = False
                method_start_line = ""
            # skip old body
        elif search_pattern.search(line):
            in_method = True
            method_start_line = line
        else:
            modified_lines.append(line)

    with open(file_path, 'w', encoding="utf-8") as file:
        file.writelines(modified_lines)
    logging.info(f"Completed modification for checkSysAppCrack method in file: {file_path}")


def modify_checkappsignature(file_path):
    logging.info(f"Modifying checkAppSignature method in file: {file_path}")
    with open(file_path, 'r', encoding="utf-8") as file:
        lines = file.readlines()

    modified_lines = []
    in_method = False
    method_start_line = ""
    search_pattern = re.compile(
        r'\.method.*checkAppSignature\(\[Landroid/content/pm/Signature;Ljava/lang/String;Z\)Z'
    )

    for line in lines:
        if in_method:
            if line.strip() == '.end method':
                modified_lines.append(method_start_line)
                modified_lines.append("    .registers 10\n")
                modified_lines.append("    const/4 v0, 0x1\n")
                modified_lines.append("    return v0\n")
                modified_lines.append(line)
                in_method = False
                method_start_line = ""
            # skip old body
        elif search_pattern.search(line):
            in_method = True
            method_start_line = line
        else:
            modified_lines.append(line)

    with open(file_path, 'w', encoding="utf-8") as file:
        file.writelines(modified_lines)
    logging.info(f"Completed modification for checkAppSignature method in file: {file_path}")


def modify_smali_files(directories):
    # Các file smali cần xử lý
    classes_to_modify = [
        'com/android/server/am/ActivityManagerServiceImpl$1.smali',
        'com/android/server/input/InputManagerServiceStubImpl.smali',
        'com/android/server/inputmethod/InputMethodManagerServiceImpl.smali',
        'com/android/server/wm/MiuiSplitInputMethodImpl.smali',
        'com/android/server/wm/WindowManagerServiceImpl.smali',
        'com/miui/server/SecurityManagerService.smali'
    ]

    search_string = "com.baidu.input_mi"
    replace_string = "com.google.android.inputmethod.latin"

    for directory in directories:
        for class_file in classes_to_modify:
            file_path = os.path.join(directory, class_file)
            if os.path.exists(file_path):
                logging.info(f"Found file: {file_path}")

                # Thay chuỗi trong các class input method
                if class_file in [
                    'com/android/server/am/ActivityManagerServiceImpl$1.smali',
                    'com/android/server/input/InputManagerServiceStubImpl.smali',
                    'com/android/server/inputmethod/InputMethodManagerServiceImpl.smali',
                    'com/android/server/wm/MiuiSplitInputMethodImpl.smali'
                ]:
                    replace_string_in_file(file_path, search_string, replace_string)

                # Patch notAllowCaptureDisplay
                if class_file == 'com/android/server/wm/WindowManagerServiceImpl.smali':
                    modify_not_allow_capture_display(file_path)

                # Patch checkSysAppCrack & checkAppSignature
                if class_file == 'com/miui/server/SecurityManagerService.smali':
                    modify_checksysappcrack(file_path)
                    modify_checkappsignature(file_path)
            else:
                logging.warning(f"File not found: {file_path}")


if __name__ == "__main__":
    cwd = os.getcwd()
    search_pattern = os.path.join(cwd, "jar_temp/miui-services.jar.out", "classes*.dex.out")
    directories = glob.glob(search_pattern)
    modify_smali_files(directories)
