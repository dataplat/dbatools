Function Set-DbaMaxMemory
{
    <# 
        .SYNOPSIS 
            Sets SQL Server 'Max Server Memory' configuration setting to a new value then displays information this setting. 

        .DESCRIPTION
            Sets SQL Server max memory then displays information relating to SQL Server Max Memory configuration settings. 

            Inspired by Jonathan Kehayias's post about SQL Server Max memory (http://bit.ly/sqlmemcalc), this uses a formula to 
            determine the default optimum RAM to use, then sets the SQL max value to that number.

            Jonathan notes that the formula used provides a *general recommendation* that doesn't account for everything that may 
            be going on in your specific environment.

        .PARAMETER SqlInstance
            Allows you to specify a comma separated list of servers to query.

        .PARAMETER MaxMb
            Specifies the max megabytes

        .PARAMETER SqlCredential 
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
          
            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.  
         
            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials 
        	being passed as credentials. To connect as a different Windows user, run PowerShell as that user. 

        .PARAMETER Collection
            Results of Get-DbaMaxMemory to be passed into the command
    
        .PARAMETER Silent
            Replaces user friendly yellow warnings with bloody red exceptions of doom!
            Use this if you want the function to throw terminating errors you want to catch.
    
        .PARAMETER WhatIf
            Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
        .PARAMETER Confirm
            Prompts you for confirmation before running the cmdlet.

        .EXAMPLE 
            Set-DbaMaxMemory sqlserver1

            Set max memory to the recommended MB on just one server named "sqlserver1"

        .EXAMPLE 
            Set-DbaMaxMemory -SqlInstance sqlserver1 -MaxMb 2048

            Explicitly max memory to 2048 MB on just one server, "sqlserver1"

        .EXAMPLE 
            Get-SqlRegisteredServerName -SqlInstance sqlserver| Test-DbaMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory

            Find all servers in SQL Server Central Management server that have Max SQL memory set to higher than the total memory 
            of the server (think 2147483647), then pipe those to Set-DbaMaxMemory and use the default recommendation.

        .NOTES 
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire

            This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

            This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

            You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

        .LINK 
            https://dbatools.io/Set-DbaMaxMemory
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    Param (
        [Parameter(Position = 0)]
        [Alias("ServerInstance", "SqlServer", "SqlServers", 'ComputerName')]
        [object]
        $SqlInstance,
        
        [Parameter(Position = 1)]
        [int]
        $MaxMb,
        
        [Parameter(ValueFromPipeline = $True)]
        [object]
        $Collection,
        
        [Alias('Credential')]
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        
        [switch]
        $Silent
    )
    Process
    {
        if ($SqlInstance.length -eq 0 -and $collection -eq $null)
        {
            Stop-Function -Silent $Silent -Category InvalidArgument -Message "You must specify a server list source using -SqlInstance or you can pipe results from Test-DbaMaxMemory"
            return
        }
        
        if ($MaxMB -eq 0)
        {
            $UseRecommended = $true
        }
        
        if ($Collection -eq $null)
        {
            $Collection = Test-DbaMaxMemory -SqlServer $SqlServer -SqlCredential $SqlCredential
        }
        
        # We ignore errors, because this will error if we pass the same collection items twice.
        # Given that it is an engine internal command, there is no other plausible error it could encounter.
        $Collection | Add-Member -NotePropertyName OldMaxValue -NotePropertyValue 0 -ErrorAction Ignore
        
        foreach ($row in $Collection)
        {
            if ($row.server -eq $null)
            {
                $row = Test-DbaMaxMemory -SqlInstance $row
                $row | Add-Member -NotePropertyName OldMaxValue -NotePropertyValue 0
            }
            
            Write-Verbose "Attempting to connect to $($row.server)"
            
            try
            {
                $server = Connect-SqlServer -SqlServer $row.server -SqlCredential $SqlCredential -ErrorAction Stop
            }
            catch
            {
                Stop-Function -Message "Can't connect to $($row.server) or access denied. Skipping." -Silent $Silent -Category ConnectionError -InnerErrorRecord $_ -Target $row -Continue
            }
            
            if (!(Test-SqlSa -SqlInstance $server))
            {
                Stop-Function -Message "Not a sysadmin on $($row.server). Skipping." -Silent $Silent -Category PermissionDenied -InnerErrorRecord $_ -Target $row -Continue
            }
            
            $row.OldMaxValue = $row.SqlMaxMB
            
            try
            {
                if ($UseRecommended)
                {
                    Write-Verbose "Changing $($row.server) SQL Server max from $($row.SqlMaxMB) to $($row.RecommendedMB) MB"
                    
                    if ($row.RecommendedMB -eq 0 -or $row.RecommendedMB -eq $null)
                    {
                        $maxmem = (Test-DbaMaxMemory -SqlInstance $server).RecommendedMB
                        Write-Warning $maxmem
                        $server.Configuration.MaxServerMemory.ConfigValue = $maxmem
                    }
                    else
                    {
                        
                        $server.Configuration.MaxServerMemory.ConfigValue = $row.RecommendedMB
                    }
                }
                else
                {
                    Write-Verbose "Changing $($row.server) SQL Server max from $($row.SqlMaxMB) to $MaxMB MB"
                    $server.Configuration.MaxServerMemory.ConfigValue = $MaxMB
                }
                if ($PSCmdlet.ShouldProcess($row.Server, "Changing maximum memory from $($row.OldMaxValue) to $($server.Configuration.MaxServerMemory.ConfigValue)"))
                {
                    try
                    {
                        $server.Configuration.Alter()
                        $row.SqlMaxMB = $server.Configuration.MaxServerMemory.ConfigValue
                    }
                    catch
                    {
                        Stop-Function -Message "Failed to apply configuration change for $($row.Server): $($_.Exception.Message)" -Silent $Silent -InnerErrorRecord $_ -Target $row -Continue
                    }
                }
            }
            catch
            {
                Stop-Function -Message "Could not modify Max Server Memory for $($row.server): $($_.Exception.Message)" -Silent $Silent -InnerErrorRecord $_ -Target $row -Continue
            }
            
            $row | Select-Object Server, TotalMB, OldMaxValue, @{ name = "CurrentMaxValue"; expression = { $_.SqlMaxMB } }
        }
    }
}
