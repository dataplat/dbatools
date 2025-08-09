function Get-TestArtifact {
    <#
    .SYNOPSIS
        Gets test artifacts from an AppVeyor job.

    .DESCRIPTION
        Retrieves test failure summary artifacts from an AppVeyor job.

    .PARAMETER JobId
        The AppVeyor job ID to get artifacts from.

    .NOTES
        Tags: AppVeyor, Testing, Artifacts
        Author: dbatools team
        Requires: APPVEYOR_API_TOKEN environment variable
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string[]]$JobId
    )

    function Get-JsonFromContent {
        param([Parameter(ValueFromPipeline)]$InputObject)
        process {
            if ($null -eq $InputObject) { return $null }

            # AppVeyor often returns PSCustomObject with .Content (string) and .Created
            $raw = if ($InputObject -is [string] -or $InputObject -is [byte[]]) {
                $InputObject
            } elseif ($InputObject.PSObject.Properties.Name -contains 'Content') {
                $InputObject.Content
            } else {
                [string]$InputObject
            }

            $s = if ($raw -is [byte[]]) { [Text.Encoding]::UTF8.GetString($raw) } else { [string]$raw }
            $s = $s.TrimStart([char]0xFEFF)  # strip BOM
            if ($s -notmatch '^\s*[\{\[]') {
                throw "Artifact body is not JSON. Starts with: '$($s.Substring(0,1))'."
            }
            $s | ConvertFrom-Json -Depth 50
        }
    }

    foreach ($id in $JobId) {
        Write-Verbose ("Fetching artifacts for job {0}" -f $id)
        $list = Invoke-AppVeyorApi "buildjobs/$id/artifacts"
        if (-not $list) { Write-Warning ("No artifacts for job {0}" -f $id); continue }

        $targets = $list | Where-Object { $_.fileName -match 'TestFailureSummary.*\.json' }
        if (-not $targets) {
            continue
        }

        foreach ($art in $targets) {
            $resp = Invoke-AppVeyorApi "buildjobs/$id/artifacts/$($art.fileName)"

            $parsed = $null
            $rawOut = $null
            $created = if ($resp.PSObject.Properties.Name -contains 'Created') { $resp.Created } else { $art.created }

            try {
                $parsed = $resp | Get-JsonFromContent
            } catch {
                $rawOut = if ($resp.PSObject.Properties.Name -contains 'Content') { [string]$resp.Content } else { [string]$resp }
                Write-Warning ("Failed to parse {0} in job {1}: {2}" -f $art.fileName, $id, $_.Exception.Message)
            }

            [pscustomobject]@{
                JobId      = $id
                FileName   = $art.fileName
                Type       = $art.type
                Size       = $art.size
                Created    = $created
                Content    = $parsed
                Raw        = $rawOut
            }
        }
    }
}
