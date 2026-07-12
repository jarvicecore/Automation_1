#Requires -Version 7
<#
.SYNOPSIS
    Applies the platform-level security configuration for this repository.

.DESCRIPTION
    The workflows in .github/workflows/ are only half the story. They can be
    bypassed entirely by anyone who can push to main, disable a check, or add a
    workflow that exfiltrates secrets. This script applies the settings that make
    the pipeline non-optional:

      1. Repository security features (secret scanning, push protection,
         Dependabot, private vulnerability reporting)
      2. Actions platform hardening (read-only default token, no self-approval,
         allow-listed actions)
      3. A branch ruleset on main (required PR, code-owner review, required
         status checks, signed commits, linear history, no force-push, no
         deletion) that applies to ADMINS TOO
      4. The six deployment environments, with their reviewer gates, wait timers
         and branch policies
      5. Promotion labels

    Idempotent. Safe to re-run; re-run it after changing team names.

.PARAMETER Repo
    owner/name. Defaults to the current repo's origin remote.

.PARAMETER DryRun
    Print what would change without calling the API.

.EXAMPLE
    ./scripts/bootstrap-github.ps1 -DryRun
    ./scripts/bootstrap-github.ps1

.NOTES
    Requires: gh CLI, authenticated with admin rights on the repo.
    Some settings (secret scanning / code scanning on PRIVATE repos, rulesets on
    private repos in Free plans) require GitHub Advanced Security or a paid plan.
    Those calls are allowed to fail with a clear warning rather than aborting.
#>

[CmdletBinding()]
param(
    [string] $Repo,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# EDIT ME. These must be real teams in your org, or reviewer gates are skipped.
# ---------------------------------------------------------------------------
$Teams = @{
    Platform        = 'platform-engineering'
    Security        = 'security'
    QA              = 'qa'
    ReleaseManagers = 'release-managers'
    BusinessOwners  = 'business-owners'
    Training        = 'training'
}

# Environment gates. wait_timer is in MINUTES.
$Environments = @(
    @{ Name = 'dev';   Reviewers = @();                                            Wait = 0;  Desc = 'Auto-deployed by CI on merge to main.' }
    @{ Name = 'qa';    Reviewers = @($Teams.QA);                                   Wait = 0;  Desc = 'First promotion gate. Binary promotion starts here.' }
    @{ Name = 'stage'; Reviewers = @($Teams.QA, $Teams.ReleaseManagers);           Wait = 0;  Desc = 'Production rehearsal.' }
    @{ Name = 'uat';   Reviewers = @($Teams.ReleaseManagers, $Teams.BusinessOwners); Wait = 0; Desc = 'Business acceptance.' }
    @{ Name = 'prod';  Reviewers = @($Teams.ReleaseManagers, $Teams.Security);     Wait = 10; Desc = 'Production. 10-minute abort window before deploy begins.' }
    @{ Name = 'train'; Reviewers = @($Teams.ReleaseManagers, $Teams.Training);     Wait = 0;  Desc = 'Training, mirrors production.' }
)

# Actions allow-list. Anything not matched here cannot run in this repository --
# which is what stops a compromised or typosquatted action from being introduced
# by a PR. Keep this in lockstep with the actions actually used in .github/workflows/.
$AllowedActions = @(
    'step-security/harden-runner@*'
    'github/codeql-action@*'
    'ossf/scorecard-action@*'
    'anchore/sbom-action@*'
    'SonarSource/sonarqube-scan-action@*'
)

# ---------------------------------------------------------------------------

function Write-Step { param($m) Write-Host "`n=== $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  [ok]   $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  [warn] $m" -ForegroundColor Yellow }
function Write-Skip { param($m) Write-Host "  [skip] $m" -ForegroundColor DarkGray }

# Invoke gh api, tolerating failures for settings that need a higher plan.
function Invoke-GhApi {
    param(
        [string]   $Method,
        [string]   $Path,
        [object]   $Body,
        [string]   $What,
        [switch]   $Tolerate
    )

    if ($DryRun) {
        Write-Skip "$Method $Path  ($What)"
        if ($Body) { Write-Host ($Body | ConvertTo-Json -Depth 10 -Compress) -ForegroundColor DarkGray }
        return $true
    }

    try {
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 10 -Compress
            $json | gh api --method $Method $Path --input - --silent 2>&1 | Out-Null
        }
        else {
            gh api --method $Method $Path --silent 2>&1 | Out-Null
        }

        if ($LASTEXITCODE -ne 0) { throw "gh api exited $LASTEXITCODE" }
        Write-Ok $What
        return $true
    }
    catch {
        if ($Tolerate) {
            Write-Warn "$What -- not applied. Usually means the plan/licence does not include it (GitHub Advanced Security, or rulesets on private repos)."
            return $false
        }
        throw "Failed: $What`n$_"
    }
}

# --- Preflight -------------------------------------------------------------

Write-Step 'Preflight'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'gh CLI not found. Install from https://cli.github.com/'
}

if (-not $Repo) {
    $Repo = (gh repo view --json nameWithOwner --jq '.nameWithOwner')
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine repo. Pass -Repo owner/name.' }
}
$Owner = $Repo.Split('/')[0]
Write-Ok "Repository: $Repo"
if ($DryRun) { Write-Warn 'DRY RUN -- no changes will be made.' }

# Resolve teams to IDs up front. A team that does not exist becomes a warning,
# not a crash -- but its environment gate will be left open, so it matters.
Write-Step 'Resolving teams'
$TeamIds = @{}
foreach ($slug in ($Teams.Values | Sort-Object -Unique)) {
    $id = gh api "orgs/$Owner/teams/$slug" --jq '.id' 2>$null
    if ($LASTEXITCODE -eq 0 -and $id) {
        $TeamIds[$slug] = [int]$id
        Write-Ok "$slug -> $id"
    }
    else {
        Write-Warn "Team '$slug' not found in org '$Owner'. Environments gated on it will have NO required reviewer."
    }
}

# --- 1. Repository security features ---------------------------------------

Write-Step '1. Repository security features'

Invoke-GhApi -Method PUT -Path "repos/$Repo/vulnerability-alerts" `
    -What 'Dependabot alerts enabled' -Tolerate | Out-Null

Invoke-GhApi -Method PUT -Path "repos/$Repo/automated-security-fixes" `
    -What 'Dependabot security updates enabled' -Tolerate | Out-Null

Invoke-GhApi -Method PUT -Path "repos/$Repo/private-vulnerability-reporting" `
    -What 'Private vulnerability reporting enabled' -Tolerate | Out-Null

Invoke-GhApi -Method PATCH -Path "repos/$Repo" -What 'Secret scanning + push protection enabled' -Tolerate -Body @{
    security_and_analysis = @{
        secret_scanning                  = @{ status = 'enabled' }
        # Push protection is the one that actually prevents the leak: it rejects
        # the push containing the credential, rather than alerting after the fact.
        secret_scanning_push_protection  = @{ status = 'enabled' }
        secret_scanning_validity_checks  = @{ status = 'enabled' }
    }
} | Out-Null

Invoke-GhApi -Method PATCH -Path "repos/$Repo" -What 'Merge hygiene (squash-only, delete branch on merge)' -Body @{
    allow_merge_commit    = $false
    allow_rebase_merge    = $false
    allow_squash_merge    = $true
    delete_branch_on_merge = $true
    allow_auto_merge      = $true
} | Out-Null

# --- 2. Actions platform hardening -----------------------------------------

Write-Step '2. Actions platform hardening'

# Read-only token by default. Any job needing more must say so explicitly, which
# is visible in review. This single setting neuters most workflow-injection
# attacks, because the injected code inherits a token that cannot write.
Invoke-GhApi -Method PUT -Path "repos/$Repo/actions/permissions/workflow" `
    -What 'Default GITHUB_TOKEN is read-only; workflows cannot approve PRs' -Body @{
        default_workflow_permissions      = 'read'
        can_approve_pull_request_reviews  = $false
    } | Out-Null

Invoke-GhApi -Method PUT -Path "repos/$Repo/actions/permissions" `
    -What 'Actions restricted to an allow-list' -Tolerate -Body @{
        enabled         = $true
        allowed_actions = 'selected'
    } | Out-Null

Invoke-GhApi -Method PUT -Path "repos/$Repo/actions/permissions/selected-actions" `
    -What "Allow-list applied ($($AllowedActions.Count) third-party patterns + GitHub-owned)" -Tolerate -Body @{
        github_owned_allowed = $true    # actions/*  -- first-party
        verified_allowed     = $false   # do NOT blanket-trust the "verified creator" badge
        patterns_allowed     = $AllowedActions
    } | Out-Null

# Fork PRs must never silently get a token or reach secrets.
Invoke-GhApi -Method PUT -Path "repos/$Repo/actions/permissions/fork-pr-workflows" `
    -What 'Fork PR workflows require approval from a maintainer' -Tolerate -Body @{
        run_workflows_from_fork_pull_requests = $false
    } | Out-Null

# --- 3. Branch ruleset on main ---------------------------------------------

Write-Step '3. Branch ruleset on main'

$rulesetPath = Join-Path $PSScriptRoot '..' '.github' 'rulesets' 'main.json'
if (-not (Test-Path $rulesetPath)) {
    Write-Warn "Ruleset file not found at $rulesetPath -- skipping."
}
else {
    $ruleset = Get-Content $rulesetPath -Raw | ConvertFrom-Json
    $existing = gh api "repos/$Repo/rulesets" --jq '.[] | select(.name=="main-protection") | .id' 2>$null

    if ($LASTEXITCODE -eq 0 -and $existing) {
        Invoke-GhApi -Method PUT -Path "repos/$Repo/rulesets/$existing" `
            -What 'Ruleset "main-protection" updated' -Tolerate -Body $ruleset | Out-Null
    }
    else {
        Invoke-GhApi -Method POST -Path "repos/$Repo/rulesets" `
            -What 'Ruleset "main-protection" created' -Tolerate -Body $ruleset | Out-Null
    }
}

# --- 4. Deployment environments --------------------------------------------

Write-Step '4. Deployment environments'

foreach ($e in $Environments) {
    $reviewers = @()
    foreach ($slug in $e.Reviewers) {
        if ($TeamIds.ContainsKey($slug)) {
            $reviewers += @{ type = 'Team'; id = $TeamIds[$slug] }
        }
    }

    $body = @{
        wait_timer          = $e.Wait
        # Stops the person who requested the promotion from also approving it.
        # Separation of duties, enforced by the platform rather than by policy.
        prevent_self_review = ($reviewers.Count -gt 0)
        reviewers           = $reviewers
        deployment_branch_policy = @{
            # Only main can deploy anywhere. A feature branch cannot reach an
            # environment even if someone hand-crafts a workflow_dispatch.
            protected_branches     = $true
            custom_branch_policies = $false
        }
    }

    $gate = if ($reviewers.Count -gt 0) { "$($reviewers.Count) reviewer team(s)" } else { 'NO REVIEWER GATE' }
    $wait = if ($e.Wait -gt 0) { ", $($e.Wait)m wait" } else { '' }

    Invoke-GhApi -Method PUT -Path "repos/$Repo/environments/$($e.Name)" `
        -What "Environment '$($e.Name)' -- $gate$wait" -Body $body | Out-Null

    if ($reviewers.Count -eq 0 -and $e.Name -ne 'dev') {
        Write-Warn "  '$($e.Name)' has no required reviewers. Anyone who can merge can deploy to it."
    }
}

# --- 5. Labels --------------------------------------------------------------

Write-Step '5. Promotion labels'

$labels = @(
    @{ name = 'promotion'; color = '0E8A16'; description = 'Environment promotion PR -- moves an existing artifact, no rebuild' }
    @{ name = 'env:qa';    color = 'FBCA04'; description = 'Targets QA' }
    @{ name = 'env:stage'; color = 'FBCA04'; description = 'Targets Stage' }
    @{ name = 'env:uat';   color = 'FBCA04'; description = 'Targets UAT' }
    @{ name = 'env:prod';  color = 'B60205'; description = 'Targets Production' }
    @{ name = 'env:train'; color = 'C5DEF5'; description = 'Targets Training' }
    @{ name = 'dependencies'; color = '0366D6'; description = 'Dependency update' }
    @{ name = 'security';  color = 'D93F0B'; description = 'Security-relevant' }
    @{ name = 'github-actions'; color = '0366D6'; description = 'CI/CD change' }
)

foreach ($l in $labels) {
    if ($DryRun) { Write-Skip "label $($l.name)"; continue }
    gh label create $l.name --color $l.color --description $l.description --force --repo $Repo 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "label $($l.name)" } else { Write-Warn "label $($l.name) failed" }
}

# --- Done -------------------------------------------------------------------

Write-Step 'Remaining manual steps'
@"
  These cannot be set via the API and must be done once in the UI or org settings:

  1. Repository secrets / variables (Settings > Secrets and variables > Actions):
       vars.ENABLE_SNYK            = true          (once you have a licence)
       secrets.SNYK_TOKEN          = <token>
       vars.ENABLE_SONAR           = true
       vars.SONAR_HOST_URL         = https://sonarqube.your-corp.example
       secrets.SONAR_TOKEN         = <token>
       vars.CODEQL_LANGUAGES_JSON  = ["actions","python"]   (match your stack)

  2. Per-environment variables/secrets (Settings > Environments > <env>):
       vars.EXTRACT_TARGET         = where extracts land for that environment
       vars.ENVIRONMENT_URL        = link shown on the deployment (optional)
       secrets.EXTRACT_CREDENTIALS = only if you cannot use OIDC federation

  3. GitHub App for promotion PRs (IMPORTANT -- so they trigger CI):
       Create an App with contents:write + pull_requests:write, install it here,
       then set vars.PROMOTION_APP_ID and secrets.PROMOTION_APP_PRIVATE_KEY.
       Without it, promotion PRs open with ZERO status checks and can be merged
       unverified -- GitHub does not trigger workflows for PRs opened with the
       default GITHUB_TOKEN. This is the one gap that undermines the model.

  Note: the ruleset already requires the 'ci-passed' check. Until CI has run once,
  PRs will sit blocked waiting for it. That is the gate working, not a bug.
"@ | Write-Host -ForegroundColor White

Write-Host "`nDone.`n" -ForegroundColor Green
