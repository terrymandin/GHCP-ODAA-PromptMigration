$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$checks = 0

function Read-RepoFile([string]$RelativePath) {
    return Get-Content -Raw -Path (Join-Path $repoRoot $RelativePath)
}

function Assert-Contract([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) {
        throw "Contract check failed: $Message"
    }
}

$skill = Read-RepoFile '.github/skills/provision-azure-files-nfs/SKILL.md'
$metadata = Read-RepoFile '.github/skills/provision-azure-files-nfs/metadata.yaml'
$catalog = Read-RepoFile '.github/config/skill-catalog.yaml'
$plan = Read-RepoFile '.github/config/execution-plans.yaml'

Assert-Contract ($skill.Contains('name: provision-azure-files-nfs')) 'skill frontmatter must name the skill'
Assert-Contract ($metadata.Contains('phase: remediation')) 'metadata must place the skill in remediation'
Assert-Contract ($catalog.Contains('id: provision-azure-files-nfs')) 'catalog must register the skill'
Assert-Contract ([regex]::IsMatch($plan, '(?ms)- id: provision-azure-files-nfs\r?\n\s+when:\r?\n\s+field: migration\.transfer\.medium\r?\n\s+equals: nfs')) 'execution must be conditional on the NFS medium'
Assert-Contract ($skill.Contains('`create_azure_files`')) 'skill must distinguish Azure creation from existing storage'
Assert-Contract ($skill.Contains('Skip it for')) 'skill must skip non-NFS media'

$questionnaire = Read-RepoFile '.github/config/questionnaire.yaml'
$profileTemplate = Read-RepoFile '.github/templates/migration-profile.yaml'
$patterns = Read-RepoFile '.github/config/migration-patterns.yaml'
$provenance = Read-RepoFile '.github/config/route-provenance.yaml'

foreach ($field in @(
    'migration.transfer.nfs.action',
    'migration.transfer.nfs.azure.resource_group',
    'migration.transfer.nfs.azure.file_share_name',
    'migration.transfer.nfs.azure.private_endpoint_subnet'
)) {
    Assert-Contract ($questionnaire.Contains($field)) "questionnaire must map $field"
}
Assert-Contract ([regex]::IsMatch($questionnaire, '(?ms)^  - id: nfs_action\r?\n.*?field: migration\.transfer\.medium\r?\n\s+equals: nfs')) 'NFS action must be required only for the NFS medium'
Assert-Contract ([regex]::IsMatch($questionnaire, '(?ms)^  - id: azure_nfs_resource_group\r?\n.*?field: migration\.transfer\.nfs\.action\r?\n\s+equals: create_azure_files')) 'Azure fields must be required only for Azure creation'
Assert-Contract ($profileTemplate.Contains('nfs:')) 'profile template must contain the NFS structure'
Assert-Contract ($patterns.Contains('- migration.transfer.nfs.validated')) 'the route must require validated NFS evidence'
Assert-Contract ($provenance.Contains('zdm_host_mount_required: false')) 'provenance must reject a ZDM-host-only mount'

$provision = Read-RepoFile '.github/skills/provision-azure-files-nfs/scripts/01-provision-share.sh'
$mount = Read-RepoFile '.github/skills/provision-azure-files-nfs/scripts/02-mount-and-verify.sh'

foreach ($token in @(
    'az fileshare create',
    '--protocol NFS',
    'az network private-endpoint create',
    '--location "$vnet_region"',
    'az network private-dns',
    '--public-network-access Disabled'
)) {
    Assert-Contract ($provision.Contains($token)) "provisioning asset must contain $token"
}
Assert-Contract (-not [regex]::IsMatch($provision, '(?m)\baz\s+[^\r\n]*(delete|purge)\b')) 'provisioning asset must not delete Azure resources'
foreach ($token in @(
    'vers=4,minorversion=1',
    'SOURCE_RWX_PASS',
    'TARGET_READ_PASS',
    'CROSS_HOST_MARKER_PASS',
    'NFS_CAPACITY_PASS'
)) {
    Assert-Contract ($mount.Contains($token)) "mount asset must contain $token"
}

$agent = Read-RepoFile '.github/agents/zdm-migration.agent.md'
$rules = Read-RepoFile '.github/instructions/Phase10.instructions.md'
$report = Read-RepoFile '.github/skills/generate-readiness-report/SKILL.md'

Assert-Contract ($agent.Contains('never ask the customer for a yes/no assertion')) 'the agent must derive NFS validation from evidence'
Assert-Contract ($agent.Contains('migration.transfer.nfs.validated` is `true`')) 'the agent must gate generation on NFS validation'
Assert-Contract ($agent.Contains('separate approval')) 'Azure and host mutations must have separate approvals'
Assert-Contract ($rules.Contains('Never execute customer Azure mutations')) 'repository rules must prohibit agent-run Azure mutations'
Assert-Contract ($rules.Contains('Never overwrite or delete')) 'repository rules must prohibit destructive Azure behavior'
Assert-Contract ($report.Contains('When the selected transfer medium is NFS')) 'readiness reporting must include invoked NFS remediation'
Assert-Contract ($report.Contains('private IPs')) 'readiness reporting must redact private network details'

Write-Output "Passed $checks Azure Files NFS contract checks."