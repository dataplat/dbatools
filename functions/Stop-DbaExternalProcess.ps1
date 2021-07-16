function Stop-DbaExternalProcess {
    <#
    .SYNOPSIS
        Stops an OS process created by SQL Server

    .DESCRIPTION
        Stops an OS process created by SQL Server

        Helps when killing hung sessions with External Wait Types

        https://web.archive.org/web/20201027122300/http://vickyharp.com/2013/12/killing-sessions-with-external-wait-types/

    .PARAMETER ComputerName
        The target SQL Server host computer

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER ProcessId
        The process ID of the OS process to kill

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
        https://dbatools.io/Set-DbaExternalProcess

    .EXAMPLE
        PS C:\> Get-DbaExternalProcess -ComputerName SQL01 | Stop-DbaExternalProcess

        Kills all OS processes created by SQL Server on SQL01

    .EXAMPLE
        PS C:\> Get-DbaExternalProcess -ComputerName SQL01 | Where-Object Name -eq "cmd.exe" | Stop-DbaExternalProcess

        Kills all cmd.exe processes created by SQL Server on SQL01

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(ValueFromPipelineByPropertyname, Mandatory)]
        [DbaInstanceParameter]$ComputerName,
        [parameter(ValueFromPipelineByPropertyname)]
        [PSCredential]$Credential,
        [Alias("pid")]
        [parameter(ValueFromPipelineByPropertyname)]
        [int]$ProcessId,
        [switch]$EnableException
    )
    process {
        try {
            # gotta add ToString(), otherwise it returns null after the process is killed
            $name = (Get-DbaCmObject -ComputerName $computer -Credential $Credential -ClassName win32_process | Where-Object ProcessId -eq $ProcessId).Name.ToString()

            Invoke-Command2 -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
                Stop-Process -Id $args[0] -Force -Confirm:$false
            } -ArgumentList $ProcessId -ErrorAction Stop

            [PSCustomObject]@{
                ComputerName = $ComputerName
                ProcessId    = $ProcessId
                Name         = $Name
                Status       = "Stopped"
            }

        } catch {
            Stop-Function -Message "Error killing $ProcessId on $computer" -ErrorRecord $_ -Continue
        }
    }
}