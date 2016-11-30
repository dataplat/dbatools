Function Get-DbaMemoryUsage
{
<#
.SYNOPSIS
Get amount of memory in use by SQL Server components

.DESCRIPTION
Retrieves the amount of memory per performance counter

Default output includes columns Server, counter instance, counter, number of pages, memory in KB, memory in MB

.PARAMETER ComputerName
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Simple
Shows concise information including Server name, Database name, and the date the last time backups were performed

.NOTES
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-DbaMemoryUsage

.EXAMPLE
Get-DbaMemoryUsage -ComputerName ServerA

Returns a custom object displaying Server, counter instance, counter, number of pages, memory in KB, memory in MB

.EXAMPLE
Get-DbaMemoryUsage -ComputerName ServerA\sql987 -Simple

Returns a custom object with Server, counter instance, counter, number of pages, memory in KB, memory in MB

.EXAMPLE
Get-DbaMemoryUsage -ComputerName ServerA\sql987 | Out-Gridview

Returns a gridview displaying Server, counter instance, counter, number of pages, memory in KB, memory in MB

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("Host", "ServerInstance", "SqlInstance")]
		[string[]]$ComputerName,
		[PsCredential]$Credential,
		[switch]$Simple
	)


	BEGIN
	{
    if ($Simple)
        {
        $Memcounters = '(Total Server Memory |Target Server Memory |Connection Memory |Lock Memory |SQL Cache Memory |Optimizer Memory |Granted Workspace Memory |Cursor memory usage|Maximum Workspace)'
        $Plancounters = 'total\)\\cache pages'
        $BufManpagecounters = 'Total pages'
        }
    else
        {
        $Memcounters = '(Total Server Memory |Target Server Memory |Connection Memory |Lock Memory |SQL Cache Memory |Optimizer Memory |Granted Workspace Memory |Cursor memory usage|Maximum Workspace)'
        $Plancounters = '(cache pages|procedure plan|ad hoc sql plan|prepared SQL Plan)'
        $BufManpagecounters = '(Free pages|Reserved pages|Stolen pages|Total pages|Database pages|target pages|extension .* pages)'
        }

    }

	PROCESS
	{
        foreach ($servername in $ComputerName)
        {
            if ($servername -match '\\')
			{
				$servername = $servername.Split('\\')[0]
			}
            Write-Verbose "Connecting to $servername"
			if ( Test-Connection -ComputerName $servername -Quiet -count 1)
            {
                $availablecounters = (Get-Counter -ComputerName $servername -ListSet '*sql*:Memory Manager*').paths
                (Get-Counter -ComputerName $servername -Counter $availablecounters).countersamples | 
                    Where-Object {$_.Path -match $Memcounters} | 
                    foreach { [PSCustomObject]@{
				                ComputerName = $servername
				                Instance = $_.Path.split("\")[-2]
                                Counter = $_.Path.split("\")[-1]
				                Pages = $null
				                MemKB = $_.cookedvalue
				                MemMB = $_.cookedvalue / 1024
                                }
                            }


                $availablecounters = (Get-Counter -ComputerName $servername -ListSet '*sql*:Plan Cache*' ).paths
                (Get-Counter -ComputerName $servername -Counter $availablecounters).countersamples |
                    Where-Object {$_.Path -match $Plancounters} |
                    foreach { [PSCustomObject]@{
					            ComputerName = $servername
					            Instance = $_.Path.split("\")[-2]
                                Counter = $_.Path.split("\")[-1]
					            Pages = $_.cookedvalue
					            MemKB = $_.cookedvalue * 8192 / 1024
					            MemMB = $_.cookedvalue * 8192 / 1048576
                                }
                            }


                $availablecounters = (Get-Counter -ComputerName $Servername -ListSet "*Buffer Manager*").paths
                (Get-Counter -ComputerName $Servername -Counter $availablecounters).countersamples |
                    Where-Object {$_.Path -match $BufManpagecounters} |
                    foreach { [PSCustomObject]@{
					            ComputerName = $servername
					            Instance = $_.Path.split("\")[-2]
                                Counter = $_.Path.split("\")[-1]
					            Pages = $_.cookedvalue
					            MemKB = $_.cookedvalue * 8192 / 1024.0
					            MemMB = $_.cookedvalue * 8192 /1048576.0
                                }
                            }
            }
			else
			{
				Write-Warning "Can't connect to $servername. Moving on."
				Continue
			}
        }
    }
    END
    {}
}
