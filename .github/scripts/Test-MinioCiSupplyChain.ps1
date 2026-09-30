[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../..").Path
)

$ErrorActionPreference = "Stop"

function Get-YamlBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Indent
    )

    $prefix = [regex]::Escape((" " * $Indent) + $Name + ":")
    $nextKeyPrefix = [regex]::Escape(" " * $Indent)
    $match = [regex]::Match($Content, "(?ms)^$prefix\r?`n(?<Block>.*?)(?=^$nextKeyPrefix\S|\z)")

    if (-not $match.Success) {
        throw "Unable to find YAML block $Name at indentation $Indent."
    }

    $match.Groups["Block"].Value
}

$expectedVersion = "RELEASE.2025-10-15T17-29-55Z"
$expectedCommit = "9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a"
$expectedGoVersion = "1.24.8"
$expectedSetupGoCommit = "b7ad1dad31e06c5925ef5d2fc7ad053ef454303e"
$expectedMcChecksum = "01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891"
$expectedImage = "dbatools/minio-ci:$expectedVersion"
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
$buildLines = $buildScript -split "\r?\n"
$dockerfileLines = $dockerfile -split "\r?\n"

$requiredBuildLines = @(
    "minio_version=`"$expectedVersion`"",
    "minio_commit=`"$expectedCommit`"",
    "minio_repository=`"https://github.com/minio/minio.git`"",
    "minio_image=`"dbatools/minio-ci:`${minio_version}`"",
    "required_go_version=`"go$expectedGoVersion`"",
    "export GOTOOLCHAIN=local",
    'actual_commit="$(git -C "${source_root}" rev-parse HEAD)"',
    'actual_tag="$(git -C "${source_root}" describe --tags --exact-match)"',
    "go mod verify",
    "make build",
    'minio_version_output="$("${source_root}/minio" --version)"',
    "for notice_file in LICENSE NOTICE CREDITS; do",
    'docker build \',
    '    --build-arg "MINIO_VERSION=${minio_version}" \',
    '    --build-arg "MINIO_COMMIT=${minio_commit}" \',
    'docker image inspect "${minio_image}" > /dev/null'
)

foreach ($requiredLine in $requiredBuildLines) {
    if ($buildLines -cnotcontains $requiredLine) {
        throw "MinIO build helper is missing required line: $requiredLine"
    }
}

$normalizedBuildScript = $buildScript -replace "\r\n", "`n"
$requiredBuildBlocks = @(
    (@(
        'actual_commit="$(git -C "${source_root}" rev-parse HEAD)"'
        'if [[ "${actual_commit}" != "${minio_commit}" ]]; then'
        '    echo "Expected MinIO commit ${minio_commit}, received ${actual_commit}." >&2'
        '    exit 1'
        'fi'
    ) -join "`n"),
    (@(
        'actual_tag="$(git -C "${source_root}" describe --tags --exact-match)"'
        'if [[ "${actual_tag}" != "${minio_version}" ]]; then'
        '    echo "Expected MinIO tag ${minio_version}, received ${actual_tag}." >&2'
        '    exit 1'
        'fi'
    ) -join "`n"),
    (@(
        'read -r _ _ actual_go_version _ <<< "$(go version)"'
        'if [[ "${actual_go_version}" != "${required_go_version}" ]]; then'
        '    echo "Expected ${required_go_version}, received ${actual_go_version}." >&2'
        '    exit 1'
        'fi'
    ) -join "`n"),
    (@(
        'minio_version_output="$("${source_root}/minio" --version)"'
        'if [[ "${minio_version_output}" != *"${minio_version}"* ]]; then'
        '    echo "Built MinIO did not report ${minio_version}: ${minio_version_output}" >&2'
        '    exit 1'
        'fi'
    ) -join "`n")
)

foreach ($requiredBlock in $requiredBuildBlocks) {
    if (-not $normalizedBuildScript.Contains($requiredBlock)) {
        throw "MinIO build helper is missing a required verification block."
    }
}

$forbiddenBuildPatterns = @(
    "docker\s+push",
    "--cache-to",
    "--output\s+type=registry"
)

foreach ($pattern in $forbiddenBuildPatterns) {
    if ($buildScript -match $pattern) {
        throw "MinIO build helper publishes or externally caches the image: $pattern"
    }
}

$requiredDockerfileLines = @(
    "FROM scratch",
    "ARG MINIO_VERSION",
    "ARG MINIO_COMMIT",
    '      org.opencontainers.image.source="https://github.com/minio/minio" \',
    '      org.opencontainers.image.version="${MINIO_VERSION}" \',
    '      org.opencontainers.image.revision="${MINIO_COMMIT}" \',
    '      org.opencontainers.image.licenses="AGPL-3.0-only"',
    "COPY minio /usr/bin/minio",
    "COPY LICENSE NOTICE CREDITS /usr/share/licenses/minio/"
)

foreach ($requiredLine in $requiredDockerfileLines) {
    if ($dockerfileLines -cnotcontains $requiredLine) {
        throw "MinIO runtime Dockerfile is missing required line: $requiredLine"
    }
}

foreach ($relativeWorkflowPath in $workflowPaths) {
    $workflowPath = Join-Path -Path $RepositoryRoot -ChildPath $relativeWorkflowPath
    $workflow = Get-Content -Raw -LiteralPath $workflowPath
    $workflowLines = $workflow -split "\r?\n"

    $requiredTriggerPaths = @(
        ".github/scripts/Build-MinioCiImage.sh",
        ".github/docker/minio/**"
    )

    foreach ($eventName in @("push", "pull_request")) {
        $eventBlock = Get-YamlBlock -Content $workflow -Name $eventName -Indent 2
        $pathsBlock = Get-YamlBlock -Content $eventBlock -Name "paths" -Indent 4
        $pathLines = $pathsBlock -split "\r?\n"

        foreach ($requiredTriggerPath in $requiredTriggerPaths) {
            $triggerLine = "      - `"$requiredTriggerPath`""
            if ($pathLines -cnotcontains $triggerLine) {
                throw "$relativeWorkflowPath must trigger on $requiredTriggerPath for $eventName."
            }
        }
    }

    $requiredWorkflowLines = @(
        "        uses: actions/setup-go@$expectedSetupGoCommit # v7.0.0",
        "          go-version: `"$expectedGoVersion`"",
        "          cache: false",
        "        run: bash ./.github/scripts/Build-MinioCiImage.sh",
        ('          echo "{0}  $HOME/mc" | sha256sum --check' -f $expectedMcChecksum)
    )

    foreach ($requiredLine in $requiredWorkflowLines) {
        if ($workflowLines -cnotcontains $requiredLine) {
            throw "$relativeWorkflowPath is missing required line: $requiredLine"
        }
    }

    $escapedImage = [regex]::Escape($expectedImage)
    $minioRunMatch = [regex]::Match(
        $workflow,
        "(?ms)^\s*docker run -d \\\r?`$.*?^\s*$escapedImage server /data(?:\s+--console-address `":9001`")?\r?`$"
    )
    if (-not $minioRunMatch.Success) {
        throw "$relativeWorkflowPath does not run the expected local image $expectedImage."
    }

    $minioRunLines = @($minioRunMatch.Value -split "\r?\n" | ForEach-Object { $_.Trim() })
    $requiredRunLines = @(
        'docker run -d \',
        '--name minio \',
        '--hostname minio \',
        '--network localnet \',
        '-p 9000:9000 \',
        '-v $HOME/.minio/certs:/root/.minio/certs:ro \'
    )

    foreach ($requiredLine in $requiredRunLines) {
        if ($minioRunLines -cnotcontains $requiredLine) {
            throw "$relativeWorkflowPath MinIO docker run block is missing: $requiredLine"
        }
    }

    foreach ($environmentVariable in @("MINIO_ROOT_USER", "MINIO_ROOT_PASSWORD")) {
        $environmentPattern = '^-e "?{0}=.+"? \\$' -f [regex]::Escape($environmentVariable)
        if (-not ($minioRunLines -match $environmentPattern)) {
            throw "$relativeWorkflowPath MinIO docker run block is missing $environmentVariable."
        }
    }

    $minioImagePatterns = @(
        "(?im)(?<Image>(?:[a-z0-9][a-z0-9.-]*(?::[0-9]+)?/)+(?=[a-z0-9._-]*(?:minio|silo))[a-z0-9][a-z0-9._-]*:[a-z0-9._-]+)",
        "(?im)^\s*(?<Image>(?:minio|silo)[a-z0-9._-]*:[a-z0-9._-]+)\s+(?:minio\s+)?server\s+/data"
    )

    foreach ($imagePattern in $minioImagePatterns) {
        foreach ($imageMatch in [regex]::Matches($workflow, $imagePattern)) {
            $imageReference = $imageMatch.Groups["Image"].Value
            if ($imageReference -cne $expectedImage) {
                throw "$relativeWorkflowPath references non-allowlisted MinIO-compatible image $imageReference."
            }
        }
    }
}

Write-Host "MinIO CI supply-chain contract passed for both integration workflows."
