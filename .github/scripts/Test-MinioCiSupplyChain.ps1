[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../..").Path
)

$ErrorActionPreference = "Stop"

$expectedVersion = "RELEASE.2025-10-15T17-29-55Z"
$expectedCommit = "9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a"
$expectedGoVersion = "1.24.8"
$expectedMcChecksum = "01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891"
$buildScriptPath = Join-Path -Path $RepositoryRoot -ChildPath ".github/scripts/Build-MinioCiImage.sh"
$dockerfilePath = Join-Path -Path $RepositoryRoot -ChildPath ".github/docker/minio/Dockerfile"
$workflowPaths = @(
    ".github/workflows/integration-tests-s3.yml",
    ".github/workflows/integration-tests-external-table.yml"
)

if (-not (Test-Path -LiteralPath $buildScriptPath -PathType Leaf)) {
    throw "MinIO source-build helper was not found at $buildScriptPath"
}

if (-not (Test-Path -LiteralPath $dockerfilePath -PathType Leaf)) {
    throw "MinIO runtime Dockerfile was not found at $dockerfilePath"
}

$buildScript = Get-Content -Raw -LiteralPath $buildScriptPath
$dockerfile = Get-Content -Raw -LiteralPath $dockerfilePath

$requiredBuildPatterns = @(
    [regex]::Escape($expectedVersion),
    [regex]::Escape($expectedCommit),
    "GOTOOLCHAIN=local",
    "go mod verify",
    "make build",
    "LICENSE NOTICE CREDITS",
    "minio --version"
)

foreach ($pattern in $requiredBuildPatterns) {
    if ($buildScript -notmatch $pattern) {
        throw "MinIO build helper is missing required pattern: $pattern"
    }
}

$requiredDockerfilePatterns = @(
    "(?m)^FROM scratch$",
    "org.opencontainers.image.source",
    "org.opencontainers.image.revision",
    "org.opencontainers.image.licenses",
    "COPY minio /usr/bin/minio",
    "COPY LICENSE NOTICE CREDITS"
)

foreach ($pattern in $requiredDockerfilePatterns) {
    if ($dockerfile -notmatch $pattern) {
        throw "MinIO runtime Dockerfile is missing required pattern: $pattern"
    }
}

foreach ($relativeWorkflowPath in $workflowPaths) {
    $workflowPath = Join-Path -Path $RepositoryRoot -ChildPath $relativeWorkflowPath
    $workflow = Get-Content -Raw -LiteralPath $workflowPath

    if ($workflow -match "(?:quay\.io/minio/minio|minio/minio|pgsty/(?:minio|silo)):") {
        throw "$relativeWorkflowPath still pulls a prebuilt MinIO-compatible server image."
    }

    $requiredWorkflowPatterns = @(
        "actions/setup-go@[0-9a-f]{40}",
        "go-version:\s*[`"']?$([regex]::Escape($expectedGoVersion))[`"']?",
        [regex]::Escape("./.github/scripts/Build-MinioCiImage.sh"),
        [regex]::Escape($expectedMcChecksum),
        "sha256sum --check"
    )

    foreach ($pattern in $requiredWorkflowPatterns) {
        if ($workflow -notmatch $pattern) {
            throw "$relativeWorkflowPath is missing required pattern: $pattern"
        }
    }
}

Write-Host "MinIO CI supply-chain contract passed for both integration workflows."
