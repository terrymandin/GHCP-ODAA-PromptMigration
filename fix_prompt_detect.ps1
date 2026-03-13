$file = "C:\GitDesk\GHCP-ODAA-PromptMigration\.github\prompts\Phase10-Step2-Generate-Discovery-Scripts.prompt.md"
$lines = [System.IO.File]::ReadAllLines($file, [System.Text.Encoding]::UTF8)

# Lines 780-879 (1-indexed) = indices 779-878 (0-indexed)
# Line 780 = "  # Auto-detect ZDM_HOME and JAVA_HOME (for ZDM server script)"
# Line 879 = "  ```" (end of code block)
$startIdx = 779
$endIdx = 878

Write-Host "Verifying start line ($($startIdx+1)): $($lines[$startIdx])"
Write-Host "Verifying end line ($($endIdx+1)): $($lines[$endIdx])"
Write-Host "Line after block ($($endIdx+2)): $($lines[$endIdx+1])"

$newBlock = @(
    "  # Auto-detect ZDM_HOME and JAVA_HOME (for ZDM server script)",
    "  # NOTE: zdm_server_discovery.sh ALWAYS runs as zdmuser.",
    "  # Access all ZDM files directly - no sudo needed.",
    "  detect_zdm_env() {",
    "      # If already set, use existing values",
    "      if [ -n `"`${ZDM_HOME:-}`"` ] && [ -n `"`${JAVA_HOME:-}`"` ]; then",
    "          return 0",
    "      fi",
    "",
    "      # Detect ZDM_HOME using multiple methods (direct access - no sudo)",
    "      if [ -z `"`${ZDM_HOME:-}`"` ]; then",
    "          local zdm_user=`"`${ZDM_USER:-zdmuser}`"",
    "",
    "          # Method 1: ZDM_HOME from login environment (set in .bash_profile by ZDM installer)",
    "          # Already running as zdmuser so if bash -l was used it is already inherited.",
    "",
    "          # Method 2: Check zdmuser's home directory for common ZDM paths",
    "          if [ -z `"`${ZDM_HOME:-}`"` ]; then",
    "              local zdm_user_home",
    "              zdm_user_home=`$(eval echo ~`$zdm_user 2>/dev/null)",
    "              if [ -n `"`$zdm_user_home`"` ]; then",
    "                  for subdir in zdmhome zdm app/zdmhome; do",
    "                      local candidate=`"`$zdm_user_home/`$subdir`"",
    "                      if [ -d `"`$candidate`"` ] && [ -f `"`$candidate/bin/zdmcli`"` ]; then",
    "                          export ZDM_HOME=`"`$candidate`"",
    "                          break",
    "                      fi",
    "                  done",
    "              fi",
    "          fi",
    "",
    "          # Method 3: Common ZDM installation locations (accessible by zdmuser directly)",
    "          if [ -z `"`${ZDM_HOME:-}`"` ]; then",
    "              for path in /u01/app/zdmhome /u01/zdm /u01/app/zdm /opt/zdm \",
    "                          `"/home/`${ZDM_USER:-zdmuser}/zdmhome`" `"`$HOME/zdmhome`"; do",
    "                  if [ -d `"`$path`"` ] && [ -f `"`$path/bin/zdmcli`"` ]; then",
    "                      export ZDM_HOME=`"`$path`"",
    "                      break",
    "                  fi",
    "              done",
    "          fi",
    "",
    "          # Method 4: Find zdmcli binary (plain find - no sudo)",
    "          if [ -z `"`${ZDM_HOME:-}`"` ]; then",
    "              local zdmcli_path",
    "              zdmcli_path=`$(find /u01 /opt /home -name `"zdmcli`" -type f 2>/dev/null | head -1)",
    "              if [ -n `"`$zdmcli_path`"` ]; then",
    "                  export ZDM_HOME=`"`$(dirname `"`$(dirname `"`$zdmcli_path`")`")`"",
    "              fi",
    "          fi",
    "      fi",
    "",
    "      # Detect JAVA_HOME - check ZDM's bundled JDK first",
    "      if [ -z `"`${JAVA_HOME:-}`"` ]; then",
    "          if [ -n `"`${ZDM_HOME:-}`"` ] && [ -d `"`${ZDM_HOME}/jdk`"` ]; then",
    "              export JAVA_HOME=`"`${ZDM_HOME}/jdk`"",
    "          elif command -v java >/dev/null 2>&1; then",
    "              local java_path",
    "              java_path=`$(readlink -f `"`$(command -v java)`"` 2>/dev/null)",
    "              [ -n `"`$java_path`"` ] && export JAVA_HOME=`"`${java_path%/bin/java}`"",
    "          else",
    "              for path in /usr/java/latest /usr/java/jdk* /usr/lib/jvm/java-* /opt/java/jdk*; do",
    "                  if [ -d `"`$path`"` ] && [ -f `"`$path/bin/java`"` ]; then",
    "                      export JAVA_HOME=`"`$path`"",
    "                      break",
    "                  fi",
    "              done",
    "          fi",
    "      fi",
    "  }",
    "  ```"
)

Write-Host "New block lines: $($newBlock.Count)"

$before = $lines[0..($startIdx-1)]
$after = $lines[($endIdx+1)..($lines.Count-1)]
$newLines = $before + $newBlock + $after

[System.IO.File]::WriteAllLines($file, $newLines, [System.Text.Encoding]::UTF8)
Write-Host "File written. Total lines: $($newLines.Count)"

# Verify
$check = sls "_zdm_sudo" $file
if ($check) {
    Write-Host "REMAINING _zdm_sudo occurrences:"
    $check | ForEach-Object { Write-Host "  Line $($_.LineNumber): $($_.Line)" }
} else {
    Write-Host "SUCCESS: No _zdm_sudo references remain in the prompt!"
}
