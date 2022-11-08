$scriptBlock = {
    $script:___ScriptName = 'dbatools-teppasynccache'

    # Defer module import to avoid collisions and reduce CPU impact
    Start-Sleep -Seconds 15
    $dbatoolsPath = Join-Path -Path ([Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase) -ChildPath "dbatools.psd1"
    Import-Module $dbatoolsPath
    $script:dbatools = Get-Module dbatools

    #region Utility Functions
    function Get-PriorityServer {
        [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT (New-Object System.DateTime(1, 1, 1, 1, 1, 1))
    }

    function Get-ActionableServer {
        [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT ((Get-Date) - ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateInterval)) | Where-Object -Property LastUpdate -GT ((Get-Date) - ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateTimeout))
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
            if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }

            foreach ($instance in $ServerAccess) {
                if ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.ConnectionObject)
                try {
                    $server.ConnectionContext.Connect()
                } catch {
                    & $script:dbatools { Write-Message "Failed to connect to $instance" -ErrorRecord $_ -Level Debug }
                    continue
                }

                $FullSmoName = ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$instance.ConnectionObject.ConnectionString).FullSmoName.ToLowerInvariant()

                foreach ($scriptBlock in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                    $scriptName = ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Scripts.Values | Where-Object ScriptBlock -EQ $scriptBlock).Name
                    # Workaround to avoid stupid issue with scriptblock from different runspace
                    try { [ScriptBlock]::Create($scriptBlock).Invoke() }
                    catch { & $script:dbatools { Write-Message "Failed to execute TEPP $scriptName against $FullSmoName" -ErrorRecord $_ -Level Debug } }
                }

                foreach ($scriptBlock in ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsSlow)) {
                    $scriptName = ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::Scripts.Values | Where-Object ScriptBlock -EQ $scriptBlock).Name
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
            if ([Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].State -notlike "Running") {
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
        [Dataplat.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLowerInvariant()].SignalStopped()
    }
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "dbatools-teppasynccache"
if (-not ([Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled)) {
    Start-DbaRunspace -Name "dbatools-teppasynccache"
}