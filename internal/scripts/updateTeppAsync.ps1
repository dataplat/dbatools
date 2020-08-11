$scriptBlock = {
    $script:___ScriptName = 'dbatools-teppasynccache'

    # Defer module import to avoid collisions and reduce CPU impact
    Start-Sleep -Seconds 15
    $dbatoolsPath = Join-Path -Path ([Sqlcollaborative.Dbatools.dbaSystem.SystemHost]::ModuleBase) -ChildPath "dbatools.psd1"
    Import-Module $dbatoolsPath
    $script:dbatools = Get-Module dbatools

    #region Utility Functions
    function Get-PriorityServer {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT (New-Object System.DateTime(1, 1, 1, 1, 1, 1))
    }

    function Get-ActionableServer {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT ((Get-Date) - ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateInterval)) | Where-Object -Property LastUpdate -GT ((Get-Date) - ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateTimeout))
    }

    function Update-TeppCache {
        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline)]
            $ServerAccess
        )

        begin {

        }
        process {
            if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }

            foreach ($instance in $ServerAccess) {
                if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.ConnectionObject)
                try {
                    $server.ConnectionContext.Connect()
                } catch {
                    & $script:dbatools { Write-Message "Failed to connect to $instance" -ErrorRecord $_ -Level Debug }
                    continue
                }

                $FullSmoName = ([Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]$instance.ConnectionObject.ConnectionString).FullSmoName.ToLowerInvariant()

                foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                    $scriptName = ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts.Values | Where-Object ScriptBlock -EQ $scriptBlock).Name
                    # Workaround to avoid stupid issue with scriptblock from different runspace
                    try { [ScriptBlock]::Create($scriptBlock).Invoke() }
                    catch { & $script:dbatools { Write-Message "Failed to execute TEPP $scriptName against $FullSmoName" -ErrorRecord $_ -Level Debug } }
                }

                foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsSlow)) {
                    $scriptName = ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Scripts.Values | Where-Object ScriptBlock -EQ $scriptBlock).Name
                    # Workaround to avoid stupid issue with scriptblock from different runspace
                    try { [ScriptBlock]::Create($scriptBlock).Invoke() }
                    catch { & $script:dbatools { Write-Message "Failed to execute TEPP $scriptName against $FullSmoName" -ErrorRecord $_ -Level Debug } }
                }

                $server.ConnectionContext.Disconnect()

                $instance.LastUpdate = Get-Date
            }
        }
        end {

        }
    }
    #endregion Utility Functions

    try {
        #region Main Execution
        while ($true) {
            # This portion is critical to gracefully closing the script
            if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].State -notlike "Running") {
                break
            }

            Get-PriorityServer | Update-TeppCache

            Get-ActionableServer | Update-TeppCache

            Start-Sleep -Seconds 5
        }
        #endregion Main Execution
    } catch {
        & $script:dbatools { Write-Message "General Failure" -ErrorRecord $_ -Level Debug }
    } finally {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].SignalStopped()
    }
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "dbatools-teppasynccache"
if (-not ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled)) {
    Start-DbaRunspace -Name "dbatools-teppasynccache"
}