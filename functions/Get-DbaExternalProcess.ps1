function Get-DbaExternalProcess {
    <#
    .SYNOPSIS
        Gets OS processes created by SQL Server

    .DESCRIPTION
        Gets OS processes created by SQL Server

    .PARAMETER ComputerName
        The target SQL Server host computer

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Process
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaExternalProcess

    .EXAMPLE
        PS C:\> Get-DbaExternalProcess

        xyz

    .EXAMPLE
        PS C:\>
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $computername) {
            try {
                $processes = Get-DbaCmObject -ComputerName $computer -Credential $Credential -ClassName win32_process | Where-Object ParentProcessId -eq (Get-DbaCmObject -ComputerName $computer -Credential $Credential -ClassName win32_process | Where-Object ProcessName -eq "sqlservr.exe").ProcessId | Select-DefaultView -Property 'PSComputer as ComputerName', ProcessId, Name, HandleCount, WorkingSetSize, VirtualSize

                foreach ($process in $processes) {
                    [PSCustomObject]@{
                        ComputerName   = $computer
                        ProcessId      = $process.ProcessId
                        Name           = $process.Name
                        HandleCount    = $process.HandleCount
                        WorkingSetSize = $process.WorkingSetSize
                        VirtualSize    = $process.VirtualSize
                        CimObject      = $process
                    }
                }
            } catch {
                Stop-Function -Message "Failure for $computer" -ErrorRecord $_
            }
        }
    }
}