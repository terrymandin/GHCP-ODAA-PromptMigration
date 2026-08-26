[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Apply')]
    [string]$Mode = 'Plan',

    [ValidateSet('ExistingVm', 'CreateVm')]
    [string]$VmMode = 'ExistingVm',

    [Parameter(Mandatory)]
    [string]$JumpboxHost,

    [ValidateRange(1, 65535)]
    [int]$JumpboxPort = 22,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$JumpboxAlias = 'zdm-jumpbox',

    [ValidatePattern('^zdmuser$')]
    [string]$JumpboxUser = 'zdmuser',

    [Parameter(Mandatory)]
    [string]$JumpboxSshKey,

    [switch]$GenerateSshKey,

    [string]$WorkspaceRoot = (Get-Location).Path,

    [string]$VmName = 'zdm-jumpbox',
    [string]$ResourceGroup,
    [string]$Location,
    [string]$VnetName,
    [string]$SubnetName,
    [switch]$CreateVnet,
    [string]$VmImage = 'Oracle:Oracle-Linux:ol10-lvm-gen2:latest',
    [string]$VmSize = 'Standard_D2s_v3',
    [ValidateRange(30, 4095)]
    [int]$OsDiskSizeGb = 256,
    [string]$AdminUser = 'azureuser',
    [string]$SshPublicKeyPath,
    [string]$RepositoryUrl = 'https://github.com/terrymandin/GHCP-ODAA-PromptMigration.git'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$checks = New-Object System.Collections.Generic.List[object]
$remainingActions = New-Object System.Collections.Generic.List[string]
$artifactPaths = New-Object System.Collections.Generic.List[string]
$operation = if ($VmMode -eq 'CreateVm') { 'provision-and-configure' } else { 'configure-remote-ssh' }
$reportPath = Join-Path $WorkspaceRoot 'Artifacts\Phase10-Migration\Step1\remote-ssh-setup-report.md'
$readmePath = Join-Path $WorkspaceRoot 'Artifacts\Phase10-Migration\Step1\README.md'

function Write-Diagnostic {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Add-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail,
        [bool]$Required = $true
    )

    $checks.Add([pscustomobject]@{
            name = $Name
            passed = $Passed
            required = $Required
            detail = $Detail
        })
}

function Get-ResultStatus {
    $failedRequired = @($checks | Where-Object { $_.required -and -not $_.passed })
    if ($failedRequired.Count -eq 0) { return 'READY' }
    return 'ACTION REQUIRED'
}

function Complete-Run {
    param([int]$ExitCode)

    $status = Get-ResultStatus
    $result = [pscustomobject]@{
        step = 'Step01'
        operation = $operation
        status = $status
        succeeded = ($status -eq 'READY')
        checks = $checks.ToArray()
        artifactPaths = $artifactPaths.ToArray()
        remainingActions = $remainingActions.ToArray()
    }
    $result | ConvertTo-Json -Depth 6 -Compress
    exit $ExitCode
}

function Test-ExtensionInstalled {
    $extensionPath = Join-Path $env:USERPROFILE '.vscode\extensions'
    return @(Get-ChildItem -Path $extensionPath -Directory -Filter 'ms-vscode-remote.remote-ssh*' -ErrorAction SilentlyContinue).Count -gt 0
}

function Get-SshConfigPath {
    return Join-Path $env:USERPROFILE '.ssh\config'
}

function Get-HostBlock {
    param([string]$Content, [string]$Alias)
    $escapedAlias = [regex]::Escape($Alias)
    $pattern = "(?ms)^Host\s+$escapedAlias\s*$.*?(?=^Host\s+|\z)"
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) { return $match.Value.TrimEnd("`r", "`n") }
    return $null
}

function Get-DesiredHostBlock {
    return @"
Host $JumpboxAlias
    HostName $JumpboxHost
    Port $JumpboxPort
    User $JumpboxUser
    IdentityFile $JumpboxSshKey
    ServerAliveInterval 60
    ServerAliveCountMax 10
"@.Trim()
}

function Set-SshHostBlock {
    $sshDirectory = Split-Path -Parent (Get-SshConfigPath)
    $configPath = Get-SshConfigPath
    if (-not (Test-Path $sshDirectory)) {
        New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
        & icacls $sshDirectory /inheritance:r "/grant:r:$env:USERNAME`:(F)" | Out-Null
    }
    if (-not (Test-Path $configPath)) {
        New-Item -ItemType File -Path $configPath -Force | Out-Null
    }

    $content = Get-Content -Path $configPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = '' }
    $desired = Get-DesiredHostBlock
    $existing = Get-HostBlock -Content $content -Alias $JumpboxAlias
    if ($existing -eq $desired) { return 'UNCHANGED' }

    if ($null -ne $existing) {
        $escapedAlias = [regex]::Escape($JumpboxAlias)
        $pattern = "(?ms)^Host\s+$escapedAlias\s*$.*?(?=^Host\s+|\z)"
        $updated = [regex]::Replace($content, $pattern, "$desired`r`n")
    }
    elseif ([string]::IsNullOrWhiteSpace($content)) {
        $updated = "$desired`r`n"
    }
    else {
        $updated = $content.TrimEnd() + "`r`n`r`n$desired`r`n"
    }
    Set-Content -Path $configPath -Value $updated -NoNewline
    return if ($null -eq $existing) { 'ADDED' } else { 'UPDATED' }
}

function Invoke-SshCommand {
    param([string]$RemoteCommand, [string]$RemoteUser = $AdminUser)

    $errorFile = [System.IO.Path]::GetTempFileName()
    try {
        $output = & ssh '-o' 'StrictHostKeyChecking=accept-new' '-o' 'BatchMode=yes' '-p' $JumpboxPort '-i' $JumpboxSshKey "$RemoteUser@$JumpboxHost" $RemoteCommand 2> $errorFile
        return [pscustomobject]@{
            exitCode = $LASTEXITCODE
            stdout = (($output | Out-String).Trim())
            stderr = ((Get-Content -Path $errorFile -Raw).Trim())
        }
    }
    finally {
        Remove-Item -Path $errorFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RemoteCheck {
    param([string]$Name, [string]$RemoteCommand, [string]$ExpectedText)

    $result = Invoke-SshCommand -RemoteCommand $RemoteCommand
    $passed = $result.exitCode -eq 0 -and ([string]::IsNullOrEmpty($ExpectedText) -or $result.stdout -match [regex]::Escape($ExpectedText))
    $detail = if ($passed) { $result.stdout } elseif ($result.stderr) { $result.stderr } else { $result.stdout }
    Add-Check -Name $Name -Passed $passed -Detail $detail
    return $passed
}

function Invoke-NewVm {
    if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($Location) -or [string]::IsNullOrWhiteSpace($VnetName) -or [string]::IsNullOrWhiteSpace($SubnetName)) {
        throw 'ResourceGroup, Location, VnetName, and SubnetName are required when VmMode is CreateVm.'
    }
    if ([string]::IsNullOrWhiteSpace($SshPublicKeyPath) -or -not (Test-Path $SshPublicKeyPath)) {
        throw 'SshPublicKeyPath must reference an existing public key when VmMode is CreateVm.'
    }
    if ($CreateVnet) {
        & az network vnet create '--resource-group' $ResourceGroup '--name' $VnetName '--location' $Location '--address-prefix' '10.0.0.0/16' '--output' 'none'
        if ($LASTEXITCODE -ne 0) { throw 'VNet creation failed.' }
        & az network vnet subnet create '--resource-group' $ResourceGroup '--vnet-name' $VnetName '--name' $SubnetName '--address-prefix' '10.0.0.0/24' '--output' 'none'
        if ($LASTEXITCODE -ne 0) { throw 'Subnet creation failed.' }
    }

    $vmOutput = & az vm create '--resource-group' $ResourceGroup '--name' $VmName '--location' $Location '--image' $VmImage '--size' $VmSize '--os-disk-size-gb' $OsDiskSizeGb '--vnet-name' $VnetName '--subnet' $SubnetName '--admin-username' $AdminUser '--ssh-key-values' $SshPublicKeyPath '--public-ip-sku' 'Standard' '--output' 'json'
    if ($LASTEXITCODE -ne 0) { throw 'VM creation failed.' }
    $vm = $vmOutput | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($vm.publicIpAddress)) { throw 'Azure CLI did not return a public IP address.' }
    $script:JumpboxHost = $vm.publicIpAddress
    Add-Check -Name 'azure-vm' -Passed $true -Detail "Created $VmName at $JumpboxHost"
}

function Initialize-NewVm {
    $publicKeyPath = if ($SshPublicKeyPath) { $SshPublicKeyPath } else { "$JumpboxSshKey.pub" }
    if (-not (Test-Path $publicKeyPath)) {
        Add-Check -Name 'jumpbox-bootstrap' -Passed $false -Detail "Public key not found: $publicKeyPath"
        return
    }
    $publicKeyBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $publicKeyPath)))
    $commands = @(
        @{ name = 'install-tar'; command = 'sudo dnf install -y tar'; expected = '' },
        @{ name = 'install-git'; command = 'sudo dnf install -y git'; expected = '' },
        @{ name = 'clone-repository'; command = "sudo mkdir -p /home/zdmuser && if [ -d /home/zdmuser/GHCP-ODAA-PromptMigration/.github ]; then echo ALREADY_PRESENT; else sudo git clone $RepositoryUrl /home/zdmuser/GHCP-ODAA-PromptMigration; fi"; expected = '' },
        @{ name = 'create-zdmuser'; command = 'getent group zdm >/dev/null 2>&1 || sudo groupadd zdm; getent passwd zdmuser >/dev/null 2>&1 || sudo useradd -g zdm -d /home/zdmuser -M zdmuser; sudo chown -R zdmuser:zdm /home/zdmuser; sudo mkdir -p /home/zdmuser/.ssh; sudo chmod 700 /home/zdmuser/.ssh; sudo chown zdmuser:zdm /home/zdmuser/.ssh'; expected = '' },
        @{ name = 'install-zdmuser-key'; command = "echo $publicKeyBase64 | base64 -d | sudo tee /home/zdmuser/.ssh/authorized_keys >/dev/null && sudo chmod 600 /home/zdmuser/.ssh/authorized_keys && sudo chown zdmuser:zdm /home/zdmuser/.ssh/authorized_keys"; expected = '' },
        @{ name = 'create-zdm-directories'; command = 'sudo dnf install -y expect glibc-devel libnsl ncurses-compat-libs libaio unzip perl wget && sudo mkdir -p /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download && sudo chown -R zdmuser:zdm /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download'; expected = '' },
        @{ name = 'verify-jumpbox-bootstrap'; command = "stat -c '%U %G' /home/zdmuser && sudo -u zdmuser ls /home/zdmuser/GHCP-ODAA-PromptMigration/.github && stat -c '%U %G %n' /u01/app/zdmhome /u01/app/zdmbase /u01/app/zdm_download"; expected = 'zdmuser zdm' }
    )
    foreach ($item in $commands) {
        if (-not (Invoke-RemoteCheck -Name $item.name -RemoteCommand $item.command -ExpectedText $item.expected)) { return }
    }
}

function Write-StepReport {
    $status = Get-ResultStatus
    $remaining = @($remainingActions)
    if ($status -ne 'READY' -and $remaining.Count -eq 0) {
        $remaining = @('Review the failed checks in this report and rerun the plan after correcting them.')
    }
    $directory = Split-Path -Parent $reportPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $connectivity = @($checks | Where-Object { $_.name -eq 'ssh-connectivity' } | Select-Object -First 1)
    $connectivityDetail = if ($connectivity.Count -eq 1) { $connectivity[0].detail } else { 'Not run' }
    $content = @"
# Remote-SSH Setup Report
Generated: $([DateTime]::UtcNow.ToString('o'))

## Script
- Path: scripts/Phase10/Step01/Initialize-Step01Jumpbox.ps1
- Mode: Apply
- VM mode: $VmMode

## SSH Config Entry
- Config file: $(Get-SshConfigPath)
- Host alias: $JumpboxAlias
- HostName: $JumpboxHost
- Port: $JumpboxPort
- User: $JumpboxUser
- IdentityFile: $JumpboxSshKey

## Connectivity Test
- Result: $(if ($connectivity.Count -eq 1 -and $connectivity[0].passed) { 'PASS' } else { 'FAIL' })
- Detail: $connectivityDetail

## Checks
$(($checks | ForEach-Object { "- $($_.name): $(if ($_.passed) { 'PASS' } else { 'FAIL' }) - $($_.detail)" }) -join "`n")

## Status
$status

## Remaining Actions
$(($remaining | ForEach-Object { "- $_" }) -join "`n")

## Next Step
Open a Remote-SSH session to $JumpboxAlias as zdmuser, then run @Phase10-Step2-Install-ZDM.
"@
    Set-Content -Path $reportPath -Value $content
    Set-Content -Path $readmePath -Value "# Step 1 - Remote-SSH Setup Outputs`n`nSee remote-ssh-setup-report.md for the current setup status."
    $artifactPaths.Add($reportPath)
    $artifactPaths.Add($readmePath)
}

try {
    if ($GenerateSshKey -and $Mode -eq 'Apply' -and -not (Test-Path $JumpboxSshKey)) {
        $sshDirectory = Split-Path -Parent $JumpboxSshKey
        New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
        & icacls $sshDirectory /inheritance:r "/grant:r:$env:USERNAME`:(F)" | Out-Null
        & ssh-keygen '-t' 'ed25519' '-f' $JumpboxSshKey '-C' 'zdmuser@zdm-jumpbox'
        if ($LASTEXITCODE -ne 0) { throw 'SSH key generation failed.' }
        & icacls $JumpboxSshKey /inheritance:r "/grant:r:$env:USERNAME`:(F)" | Out-Null
    }
    if (-not (Test-Path $JumpboxSshKey)) {
        Add-Check -Name 'ssh-private-key' -Passed $false -Detail "Private key not found: $JumpboxSshKey"
        $remainingActions.Add('Provide an existing private SSH key or generate one through the Step 1 prompt.')
    }
    else {
        Add-Check -Name 'ssh-private-key' -Passed $true -Detail $JumpboxSshKey
    }

    $extensionInstalled = Test-ExtensionInstalled
    Add-Check -Name 'remote-ssh-extension' -Passed $extensionInstalled -Detail $(if ($extensionInstalled) { 'Installed' } else { 'Install ms-vscode-remote.remote-ssh before applying setup.' })
    if (-not $extensionInstalled) { $remainingActions.Add('Install the VS Code Remote - SSH extension.') }

    if ($Mode -eq 'Plan') {
        $planDetail = if ($VmMode -eq 'CreateVm') { 'Would create the approved Azure VM and bootstrap the jumpbox.' } else { 'Would configure the named local SSH host block and test key-based connectivity.' }
        Add-Check -Name 'execution-plan' -Passed $true -Detail $planDetail -Required $false
        Complete-Run -ExitCode $(if ((Get-ResultStatus) -eq 'READY') { 0 } else { 2 })
    }

    if ((Get-ResultStatus) -ne 'READY') {
        Write-StepReport
        Complete-Run -ExitCode 2
    }

    if ($VmMode -eq 'CreateVm') { Invoke-NewVm }
    $configResult = Set-SshHostBlock
    Add-Check -Name 'ssh-config' -Passed $true -Detail $configResult

    $connectivity = Invoke-SshCommand -RemoteCommand 'hostname' -RemoteUser $JumpboxUser
    $connectivityPassed = $connectivity.exitCode -eq 0
    $connectivityDetail = if ($connectivityPassed) { $connectivity.stdout } elseif ($connectivity.stderr) { $connectivity.stderr } else { $connectivity.stdout }
    Add-Check -Name 'ssh-connectivity' -Passed $connectivityPassed -Detail $connectivityDetail
    if (-not $connectivityPassed) { $remainingActions.Add('Verify the jumpbox host, port, and zdmuser authorized_keys entry, then rerun the script.') }

    if ($VmMode -eq 'CreateVm' -and $connectivityPassed) { Initialize-NewVm }
    Write-StepReport
    Complete-Run -ExitCode $(if ((Get-ResultStatus) -eq 'READY') { 0 } else { 2 })
}
catch {
    Add-Check -Name 'unexpected-error' -Passed $false -Detail $_.Exception.Message
    $remainingActions.Add('Correct the reported error and rerun in Plan mode before applying again.')
    if ($Mode -eq 'Apply') {
        try { Write-StepReport } catch { Write-Diagnostic "Unable to write Step 1 report: $($_.Exception.Message)" }
    }
    Write-Diagnostic $_.Exception.Message
    Complete-Run -ExitCode 1
}