$scriptBlock = {
    $script:___ScriptName = 'dbatools-teppasynccache'

    #region Utility Functions
    function Get-PriorityServer {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT (New-Object System.DateTime(1, 1, 1, 1, 1, 1))
    }

    function Get-ActionableServer {
        [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::InstanceAccess.Values | Where-Object -Property LastUpdate -LT ((Get-Date) - ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateInterval)) | Where-Object -Property LastUpdate -GT ((Get-Date) - ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateTimeout))
    }

    function Update-TeppCache {
        [CmdletBinding()]
        Param (
            [Parameter(ValueFromPipeline = $true)]
            $ServerAccess
        )

        begin {

        }
        Process {
            if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }

            foreach ($instance in $ServerAccess) {
                if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUdaterStopper) { break }
                $server = New-Object Microsoft.SqlServer.Management.Smo.Server($instance.ConnectionObject)
                try {
                    $server.ConnectionContext.Connect()
                }
                catch {
                    continue
                }

                $FullSmoName = ([Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter]$server).FullSmoName.ToLower()

                foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsFast)) {
                    # Workaround to avoid stupid issue with scriptblock from different runspace
                    [ScriptBlock]::Create($scriptBlock).Invoke()
                }

                foreach ($scriptBlock in ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppGatherScriptsSlow)) {
                    # Workaround to avoid stupid issue with scriptblock from different runspace
                    [ScriptBlock]::Create($scriptBlock).Invoke()
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
            if ([Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].State -notlike "Running") {
                break
            }

            Get-PriorityServer | Update-TeppCache

            Get-ActionableServer | Update-TeppCache

            Start-Sleep -Seconds 5
        }
        #endregion Main Execution
    }
    catch { }
    finally {
        [Sqlcollaborative.Dbatools.Runspace.RunspaceHost]::Runspaces[$___ScriptName.ToLower()].SignalStopped()
    }
}

Register-DbaRunspace -ScriptBlock $scriptBlock -Name "dbatools-teppasynccache"
if (-not ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled)) {
    Start-DbaRunspace -Name "dbatools-teppasynccache"
}
