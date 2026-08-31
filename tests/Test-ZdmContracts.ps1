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

$patterns = Read-RepoFile '.github/config/migration-patterns.yaml'
Assert-Contract ([regex]::Matches($patterns, '(?m)^    enabled: true\r?$').Count -eq 1) 'exactly one route must be enabled'
Assert-Contract ([regex]::Matches($patterns, '(?m)^    enabled: false\r?$').Count -eq 3) 'three unverified routes must be disabled'
Assert-Contract ($patterns.Contains('id: vmdb-to-odaa-physical-offline-zdm26.1')) 'the proven route ID must exist'
Assert-Contract (($patterns | Select-String -Pattern 'rsp_template:' -AllMatches).Matches.Count -eq 1) 'only the enabled route may name an RSP template'

foreach ($field in @(
    'migration.source.ssh_node',
    'migration.source.listener_endpoint',
    'migration.source.sudo_path',
    'migration.source.database_service',
    'migration.source.sys_auth_verified',
    'migration.target.ssh_node',
    'migration.target.listener_endpoint',
    'migration.target.sudo_path',
    'migration.target.oracle_home',
    'migration.target.patch_level',
    'migration.target.patch_parity_verified',
    'migration.zdm.response_file'
)) {
    Assert-Contract ($patterns.Contains("- $field")) "enabled route must require $field"
}

$questionnaire = Read-RepoFile '.github/config/questionnaire.yaml'
$mappingBlock = [regex]::Match($questionnaire, '(?ms)^profile_mapping:\r?\n(.*?)^questions:').Groups[1].Value
$mappingIds = [regex]::Matches($mappingBlock, '(?m)^  ([a-z0-9_]+):') | ForEach-Object { $_.Groups[1].Value }
$questionIds = [regex]::Matches($questionnaire, '(?m)^  - id: ([a-z0-9_]+)\r?$') | ForEach-Object { $_.Groups[1].Value }
Assert-Contract ($mappingIds.Count -eq $questionIds.Count) 'every questionnaire ID must have exactly one profile mapping'
Assert-Contract ($questionnaire.StartsWith('version: 2.2')) 'the questionnaire contract version must be 2.2'
Assert-Contract ($mappingBlock.Contains('assessment_environment: migration.metadata.assessment_environment')) 'assessment environment must map to profile metadata'
Assert-Contract ([regex]::IsMatch($questionnaire, '(?ms)^  - id: assessment_environment\r?\n.*?required: true.*?options:\r?\n      - non_production\r?\n      - production')) 'assessment environment must be required with non-production and production options'
foreach ($questionId in $questionIds) {
    Assert-Contract ($mappingIds -contains $questionId) "$questionId must have a profile mapping"
}
foreach ($questionId in @(
    'source_ssh_node',
    'source_listener_endpoint',
    'source_db_service',
    'source_sys_auth_verified',
    'target_ssh_node',
    'target_listener_endpoint',
    'target_db_patch_level',
    'zdm_release',
    'zdm_response_file'
)) {
    if ($questionId -eq 'zdm_release') {
        Assert-Contract ([regex]::IsMatch($questionnaire, '(?ms)^  - id: zdm_release\r?\n.*?required: true')) 'zdm_release must be required'
    } else {
        $conditionalPattern = "(?ms)^  - id: $([regex]::Escape($questionId))`r?`n.*?required_when:`r?`n      pattern: vmdb-to-odaa-physical-offline-zdm26\.1"
        Assert-Contract ([regex]::IsMatch($questionnaire, $conditionalPattern)) "$questionId must be conditionally required"
    }
}
Assert-Contract (-not $mappingBlock.Contains('target_patch_parity_verified:')) 'derived target patch parity must not be a questionnaire mapping'
Assert-Contract (-not $questionnaire.Contains('id: target_patch_parity_verified')) 'derived target patch parity must not be a questionnaire question'
Assert-Contract ($mappingBlock.Contains('target_db_patch_level: migration.target.patch_level')) 'target patch level must map to the target profile'

$rsp = Read-RepoFile 'tests/fixtures/zdm-response-file.rsp'
$properties = @{}
foreach ($line in ($rsp -split "`r?`n")) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $parts = $trimmed.Split('=', 2)
    Assert-Contract ($parts.Count -eq 2 -and $parts[1]) "RSP line must have a value: $trimmed"
    Assert-Contract (-not $properties.ContainsKey($parts[0])) "RSP property must be unique: $($parts[0])"
    $properties[$parts[0]] = $parts[1]
}

$expectedProperties = @(
    'MIGRATION_METHOD', 'DATA_TRANSFER_MEDIUM', 'BACKUP_PATH',
    'TGT_DB_UNIQUE_NAME', 'PLATFORM_TYPE', 'TGT_DATADG', 'TGT_REDODG',
    'TGT_RECODG', 'SKIP_FALLBACK'
)
Assert-Contract ($properties.Count -eq $expectedProperties.Count) 'RSP must contain exactly nine properties'
foreach ($property in $expectedProperties) {
    Assert-Contract ($properties.ContainsKey($property)) "RSP must contain $property"
}
Assert-Contract ($properties['MIGRATION_METHOD'] -eq 'OFFLINE_PHYSICAL') 'migration method must be OFFLINE_PHYSICAL'
Assert-Contract ($properties['PLATFORM_TYPE'] -eq 'EXACS') 'target platform must be EXACS'
Assert-Contract (-not $rsp.Contains('{{')) 'RSP must not contain unresolved placeholders'
Assert-Contract (-not $rsp.Contains('SHUTDOWN_SRC')) 'eval RSP must not shut down the source'

$command = Read-RepoFile 'tests/fixtures/zdm-eval-command.sh'
Assert-Contract ($command.Contains("-sourcenode 'source-db.example.internal'")) 'command must use the source SSH node'
Assert-Contract ($command.Contains("-targetnode 'target-ssh.example.internal'")) 'command must use the target SSH node'
Assert-Contract (-not $command.Contains("-targetnode 'target-scan.example.internal'")) 'command must not substitute the target listener endpoint'
Assert-Contract ($command.Contains("-srcarg3 'sudo_location:/usr/bin/sudo'")) 'source sudo_location is required'
Assert-Contract ($command.Contains("-tgtarg3 'sudo_location:/usr/bin/sudo'")) 'target sudo_location is required'
Assert-Contract ($command.Contains("-targethome '/u02/app/oracle/product/19.0.0.0/dbhome_1'")) 'target Oracle home is required'
Assert-Contract ([regex]::IsMatch($command, '-tdekeystorepasswd\s+\\\r?\n  -eval\s*$')) 'bare TDE prompt and final -eval flags are required'
Assert-Contract (-not [regex]::IsMatch($command, '(?i)password[:=]')) 'command must not contain a password value'
Assert-Contract (-not $command.Contains('-ignore')) 'command must not bypass checks'
Assert-Contract (-not $command.Contains('StrictHostKeyChecking=no')) 'command must not bypass host-key checks'

$migrationProfileFixture = Read-RepoFile 'tests/fixtures/migration-profile.yaml'
$network = Read-RepoFile 'tests/fixtures/network-validation.yaml'
$ssh = Read-RepoFile 'tests/fixtures/ssh-validation.yaml'
Assert-Contract ($migrationProfileFixture.Contains('ssh_node: target-ssh.example.internal')) 'profile must retain the target SSH node'
Assert-Contract ($migrationProfileFixture.Contains('listener_endpoint: target-scan.example.internal')) 'profile must retain the target listener endpoint'
Assert-Contract ([regex]::Matches($migrationProfileFixture, '(?m)^    patch_level:').Count -eq 2) 'profile must retain normalized source and target patch levels'
Assert-Contract ($migrationProfileFixture.Contains('patch_parity_verified: true')) 'profile must retain skill-derived patch parity'
Assert-Contract ($migrationProfileFixture.Contains('questionnaire_version: 2.2')) 'profile fixture must use questionnaire version 2.2'
Assert-Contract ($migrationProfileFixture.Contains('assessment_environment: non_production')) 'profile fixture must identify a sanitized non-production assessment'
Assert-Contract ($network.Contains('target_listener_endpoint: target-scan.example.internal')) 'network evidence must identify the listener endpoint'
Assert-Contract (-not $network.Contains('target-ssh.example.internal')) 'network evidence must not claim an SSH-node listener test'
Assert-Contract ($ssh.Contains('target_ssh_node: target-ssh.example.internal')) 'SSH evidence must identify the SSH node'
Assert-Contract (-not $ssh.Contains('target-scan.example.internal')) 'SSH evidence must not use the listener endpoint'

$executionPlan = Read-RepoFile '.github/config/execution-plans.yaml'
$skillCatalog = Read-RepoFile '.github/config/skill-catalog.yaml'
$evalSkill = Read-RepoFile '.github/skills/validate-zdm-eval/SKILL.md'
$sourceSkill = Read-RepoFile '.github/skills/validate-source/SKILL.md'
$targetSkill = Read-RepoFile '.github/skills/validate-target/SKILL.md'
$targetMetadata = Read-RepoFile '.github/skills/validate-target/metadata.yaml'
$agent = Read-RepoFile '.github/agents/zdm-migration.agent.md'
$phase10Rules = Read-RepoFile '.github/instructions/Phase10.instructions.md'
$provenance = Read-RepoFile '.github/config/route-provenance.yaml'
$profileTemplate = Read-RepoFile '.github/templates/migration-profile.yaml'
$readinessSkill = Read-RepoFile '.github/skills/generate-readiness-report/SKILL.md'
$readinessTemplate = Read-RepoFile '.github/skills/generate-readiness-report/templates/readiness-report.md'
$startHere = Read-RepoFile '.github/prompts/00-Start-Here.prompt.md'
Assert-Contract ($executionPlan.Contains('- validate-target')) 'target validation must run before generation'
Assert-Contract ($skillCatalog.Contains('id: validate-target')) 'target validation must be registered'
Assert-Contract ($evalSkill.Contains('source database login failures return to')) 'eval source login failures must route to validation'
Assert-Contract ($evalSkill.Contains('`validate-target`')) 'eval target patch failures must route to target validation'
Assert-Contract ($sourceSkill.Contains('FROM dba_registry_sqlpatch')) 'source validation must own source SQL patch discovery'
Assert-Contract ($sourceSkill.Contains('$ORACLE_HOME/OPatch/opatch lspatches')) 'source validation must own the source OPatch fallback'
Assert-Contract ($targetSkill.Contains('FROM dba_registry_sqlpatch')) 'target validation must own target SQL patch discovery'
Assert-Contract ($targetSkill.Contains('$ORACLE_HOME/OPatch/opatch lspatches')) 'target validation must own the target OPatch fallback'
Assert-Contract ($targetSkill.Contains('Derive `migration.target.patch_parity_verified`')) 'target validation must derive patch parity from evidence'
Assert-Contract ([regex]::IsMatch($targetSkill, 'A newer target RU\s+alone is not proof')) 'target validation must not equate a newer RU with parity'
Assert-Contract ($targetMetadata.Contains('- source_db_patch_level')) 'target validation must consume source patch level data'
Assert-Contract ($targetMetadata.Contains('- target_db_patch_level')) 'target validation must consume target patch level data'
Assert-Contract (-not $targetMetadata.Contains('- target_patch_parity_verified')) 'target validation must not consume a customer parity assertion'
Assert-Contract (-not $agent.Contains('FROM dba_registry_sqlpatch')) 'the coordinator must not embed patch-discovery SQL'
Assert-Contract (-not $agent.Contains('$ORACLE_HOME/OPatch/opatch lspatches')) 'the coordinator must not embed OPatch commands'
Assert-Contract ($agent.Contains('invoke the registered skill that owns the value or')) 'the coordinator must delegate technical evidence collection generically'
Assert-Contract ($agent.Contains('Do not reproduce those')) 'the coordinator must prohibit duplicated skill procedures'
Assert-Contract (-not $agent.Contains('When target patch evidence is needed')) 'the coordinator must not contain patch-specific dispatch logic'
Assert-Contract ($agent.Contains('Every customer-facing questionnaire prompt for a missing or invalid value must also')) 'every questionnaire prompt must offer help me check'
Assert-Contract ($agent.Contains('Treat') -and $agent.Contains('`help me check` as a request for guided discovery')) 'help me check must not be persisted as an answer'
Assert-Contract ($agent.Contains('../../Artifacts/Phase10/migration-profile.yaml')) 'the canonical Phase 10 profile must be stored under Artifacts/Phase10'
Assert-Contract ($agent.Contains('../../Artifacts/Phase10/test-answers.yaml')) 'the optional Phase 10 prefill must be read from Artifacts/Phase10'
Assert-Contract ($agent.Contains('Do not write Phase 10 outputs directly under')) 'the agent must prohibit unscoped Phase 10 outputs'
Assert-Contract ($phase10Rules.Contains('under `Artifacts/Phase10/`')) 'Phase 10 maintenance rules must require the dedicated artifact directory'
Assert-Contract ($profileTemplate.Contains('questionnaire_version: 2.2')) 'profile template must use questionnaire version 2.2'
Assert-Contract ($profileTemplate.Contains('assessment_environment:')) 'profile template must include assessment environment metadata'
Assert-Contract ($agent.Contains('representative non-production environment')) 'the coordinator must recommend non-production first'
Assert-Contract ($agent.Contains('warn') -and [regex]::IsMatch($agent, 'allow the\s+assessment to continue')) 'production assessment must warn without being blocked'
Assert-Contract ($agent.Contains('Do not generate or present ZDM execution commands without the `-eval` flag')) 'the coordinator must forbid non-eval ZDM execution commands'
Assert-Contract ($phase10Rules.Contains('This release is eval-only')) 'Phase 10 maintenance rules must keep this release eval-only'
Assert-Contract ($readinessSkill.Contains('representative non-production assessment is strongly recommended first')) 'readiness reporting must recommend non-production first when needed'
Assert-Contract ($readinessTemplate.Contains('## Scope and Limitations')) 'the readiness report must include scope limitations'
Assert-Contract ($readinessTemplate.Contains('does not prove migration success')) 'the readiness report must not overclaim eval success'
Assert-Contract ($startHere.Contains('does not establish migration, cutover, fallback, rollback, or production readiness')) 'onboarding must describe the eval-only milestone'
Assert-Contract ($provenance.Contains('../../Artifacts/Phase10/zdm-response-file.rsp')) 'RSP provenance must use the Phase 10 artifact directory'
Assert-Contract ($provenance.Contains('../../Artifacts/Phase10/zdm-eval-command.sh')) 'eval-command provenance must use the Phase 10 artifact directory'

foreach ($removedPath in @(
    'requirements/migration-questionnaire.yaml',
    'requirements/migration-patterns.yaml',
    '.github/templates/rsp/exadata-to-odaa.rsp',
    '.github/templates/rsp/exadata-to-adb.rsp',
    '.github/templates/rsp/vmdb-to-adb.rsp'
)) {
    Assert-Contract (-not (Test-Path (Join-Path $repoRoot $removedPath))) "$removedPath must remain absent"
}

Write-Output "Passed $checks ZDM contract checks."