#$FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $instance
function Get-ExportFilePath ($Path, $FilePath, $Type, $ServerName, [switch]$Unique) {
    if ($FilePath) {
        return ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath))
    }

    if (-not $Path) {
        $Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')
    }
    if (-not $Type) {
        Write-Warning "You forgot -Type"
        return
    }
    $type = $type.ToLower()

    if (-not $ServerName) {
        $ServerName = "sqlinstance"
    }

    $ServerName = $ServerName.ToString().Replace('\', '$')
    $timenow = (Get-Date -uformat (Get-DbatoolsConfigValue -FullName 'Formatting.UFormat'))
    $caller = (Get-PSCallStack)[1].Command.ToString().Replace("Export-Dba", "").ToLower()

    if ($caller -eq "RepServerSetting") {
        $caller = "replication"
    }

    $finalpath = Join-DbaPath -Path $Path -Child "$servername-$timenow-$caller.$Type"

    if ($Unique) {
        if ($null -eq $script:pathcollection) {
            $script:pathcollection = @()
        }
        if (-not ($script:pathcollection | Where-Object Name -eq $ServerName)) {
            $script:pathcollection += [pscustomobject]@{
                Name = $ServerName
                Path = ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($finalpath))
            }
            return ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($finalpath))
        }
    }

    return ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($finalpath))
}