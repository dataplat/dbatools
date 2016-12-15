Function Get-DbaMemoryUsage
{
<#
.SYNOPSIS
Get amount of memory in use by SQL Server components

.DESCRIPTION
Retrieves the amount of memory per performance counter
Default output includes columns Server, counter instance, counter, number of pages, memory in KB, memory in MB
This function requires local admin role on the targeted computers.

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
		[Alias("Host", "cn", "Server")]
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
        foreach ($Computer in $ComputerName)
        {
            Write-Verbose "Connecting to $Computer"
			if ( $reply = Resolve-DbaNetworkName -ComputerName $Computer -erroraction silentlycontinue)
            {
                $Computer = $reply.ComputerName
                Write-Verbose "$Computer is up and running"
                Write-Verbose "Searching for Memory Manager Counters on $Computer"
                try
                {
                $availablecounters = (Get-Counter -ComputerName $Computer -ListSet '*sql*:Memory Manager*' -ErrorAction SilentlyContinue ).paths
                (Get-Counter -ComputerName $Computer -Counter $availablecounters -ErrorAction SilentlyContinue ).countersamples | 
                    Where-Object {$_.Path -match $Memcounters} | 
                    foreach { [PSCustomObject]@{
				                ComputerName = $Computer
                                SqlInstance = (($_.Path.split("\")[-2]).replace("mssql`$","")).split(':')[0]
				                CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$","")).split(':')[1]
                                Counter = $_.Path.split("\")[-1]
				                Pages = $null
				                MemKB = $_.cookedvalue
				                MemMB = $_.cookedvalue / 1024
                                }
                            }
                }
                catch
                {
                Write-Verbose "No Memory Manager Counters on $Computer"
                }
                
                Write-Verbose "Searching for Plan Cache Counters on $Computer"
                try
                {
                $availablecounters = (Get-Counter -ComputerName $Computer -ListSet '*sql*:Plan Cache*' -ErrorAction SilentlyContinue ).paths
                (Get-Counter -ComputerName $Computer -Counter $availablecounters -ErrorAction SilentlyContinue ).countersamples |
                    Where-Object {$_.Path -match $Plancounters} |
                    foreach { [PSCustomObject]@{
					            ComputerName = $Computer
                                SqlInstance = (($_.Path.split("\")[-2]).replace("mssql`$","")).split(':')[0]
				                CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$","")).split(':')[1]
                                Counter = $_.Path.split("\")[-1]
					            Pages = $_.cookedvalue
					            MemKB = $_.cookedvalue * 8192 / 1024
					            MemMB = $_.cookedvalue * 8192 / 1048576
                                }
                            }
                }
                catch
                {
                Write-Verbose "No Plan Cache Counters on $Computer"
                }
                                
                Write-Verbose "Searching for Buffer Manager Counters on $Computer"
                try
                {
                $availablecounters = (Get-Counter -ComputerName $Computer -ListSet "*Buffer Manager*"  -ErrorAction SilentlyContinue ).paths
                (Get-Counter -ComputerName $Computer -Counter $availablecounters -ErrorAction SilentlyContinue ).countersamples |
                    Where-Object {$_.Path -match $BufManpagecounters} |
                    foreach { [PSCustomObject]@{
					            ComputerName = $Computer
                                SqlInstance = (($_.Path.split("\")[-2]).replace("mssql`$","")).split(':')[0]
				                CounterInstance = (($_.Path.split("\")[-2]).replace("mssql`$","")).split(':')[1]
                                Counter = $_.Path.split("\")[-1]
					            Pages = $_.cookedvalue
					            MemKB = $_.cookedvalue * 8192 / 1024.0
					            MemMB = $_.cookedvalue * 8192 /1048576.0
                                }
                            }
                }
                catch
                {
                Write-Verbose "No Buffer Manager Counters on $Computer"
                }
            }
			else
			{
				Write-Warning "Can't connect to $Computer."
				Continue
			}
        }
    }
    END
    {}
}
