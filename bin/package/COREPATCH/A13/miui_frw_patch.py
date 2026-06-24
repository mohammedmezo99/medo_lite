import os
import re
import logging
import glob

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')


def modify_compareSignatures(file_path):
    logging.info(f"Modifying compareSignatures method in file: {file_path}")
    with open(file_path, 'r', encoding="utf-8") as file:
        lines = file.readlines()

    modified_lines = []
    in_method = False
    method_start_line = ""
    search_pattern = re.compile(
        r'\.method.*compareSignatures\(\[Landroid/content/pm/Signature;\[Landroid/content/pm/Signature;\)I'
    )

    for line in lines:
        if in_method:
            if line.strip() == '.end method':
                # Add method body
                modified_lines.append(method_start_line)
                modified_lines.append("    .registers 10\n")
                modified_lines.append("    const/4 v0, 0x0\n")
                modified_lines.append("    return v0\n")
                modified_lines.append(line)  # keep .end method
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
    logging.info(f"Completed modification for compareSignatures method in file: {file_path}")


def replace_string_in_file(file_path, search_string, replace_string):
    logging.info(f"Replacing string in file: {file_path}")
    with open(file_path, 'r', encoding="utf-8") as file:
        content = file.read()

    modified_content = content.replace(search_string, replace_string)

    with open(file_path, 'w', encoding="utf-8") as file:
        file.write(modified_content)
    logging.info(f"Completed string replacement in file: {file_path}")


def modify_smali_files(directories):
    # Các class cần sửa chuỗi
    classes_replace = [
        'android/inputmethodservice/InputMethodServiceInjector.smali',
        'android/view/DisplayInfoInjector$2.smali',
        'miui/util/HapticFeedbackUtil.smali'
    ]

    # Các class cần patch compareSignatures
    classes_patch = [
        'miui/content/ExtraPackageManager.smali',
        'miui/util/CertificateUtils.smali'
    ]

    search_string = "com.baidu.input_mi"
    replace_string = "com.google.android.inputmethod.latin"

    for directory in directories:
        for class_file in classes_replace:
            file_path = os.path.join(directory, class_file)
            if os.path.exists(file_path):
                logging.info(f"Found file: {file_path}")
                replace_string_in_file(file_path, search_string, replace_string)
            else:
                logging.warning(f"File not found: {file_path}")

        for class_file in classes_patch:
            file_path = os.path.join(directory, class_file)
            if os.path.exists(file_path):
                logging.info(f"Found file: {file_path}")
                modify_compareSignatures(file_path)
            else:
                logging.warning(f"File not found: {file_path}")


if __name__ == "__main__":
    cwd = os.getcwd()
    search_pattern = os.path.join(cwd, "jar_temp/miui-framework.jar.out", "classes*.dex.out")
    directories = glob.glob(search_pattern)
    modify_smali_files(directories)
