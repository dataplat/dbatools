function Set-DbaFileStream {
    <#
    .SYNOPSIS
        Sets the status of FileStream on specified SQL Server instances

    .DESCRIPTION
        Connects to the specified SQL Server instances, and sets the status of the FileStream feature to the required value

        To perform the action, the SQL Server instance must be restarted. By default we will prompt for confirmation for this action, this can be overridden with the -Force switch

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Credential
        Login to the target server using alternative credentials.

    .PARAMETER FileStreamLevel
        The level to of FileStream to be enabled:
        0 - FileStream disabled
        1 - T-Sql Access Only
        2 - T-Sql and Win32 access enabled
        3 - T-Sql, Win32 and Remote access enabled

	.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

	.PARAMETER Force
    	Restart SQL Instance after changes.

    .PARAMETER WhatIf
    	Shows what would happen if the command runs. The command is not run.

	.PARAMETER Confirm
	    Prompts you for confirmation before running the command.

    .NOTES
        Tags: Filestream
        Author: Stuart Moore ( @napalmgram )
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Set-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel T-Sql Only
        Set-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel 1

        These commands are functionally equivalent, both will set Filestream level on server1\instance2 to T-Sql Only

    .EXAMPLE
        Get-DbaFileStream -SqlInstance server1\instance2, server5\instance5 , prod\hr | Where-Object {$_.FileSteamStateID -gt 0} | Set-DbaFileStream -FileStreamLevel 0 -Force

        Using this pipeline you can scan a range of SQL instances and disable filestream on only those on which it's enabled

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [ValidateSet("0", "1", "2", "Disabled", "T-Sql Only", "T-Sql and Win-32 Access")]
        [string]$FileStreamLevel,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $NewFileStream = $FileStreamLevel
        if ($FileStreamLevel -notin ('0', '1', '2')) {
            $NewFileStream = switch ($FileStreamLevel) {
                "Disabled" {
                    0
                }
                "T-Sql Only" {
                    1
                }
                "T-Sql and Win-32 Access" {
                    2
                }
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            if ($instance -isnot [string]) {
                $instance = $instance.SqlInstance
            }
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $FileStreamState = [int]$server.Configuration.FilestreamAccessLevel.ConfigValue
            $OutputLookup = @{
                0 = 'FileStream Disabled';
                1 = 'FileStream Enabled for T-Sql Access';
                2 = 'FileStream Enabled for T-Sql and Win-32 Access';
            }

            if ($FileStreamState -ne $NewFileStream) {
                if ($force -or $PSCmdlet.ShouldProcess($instance, "Changing from `"$($OutputLookup[$FileStreamState])`" to `"$($OutputLookup[$NewFileStream])`"")) {
                    $server.Configuration.FilestreamAccessLevel.ConfigValue = $NewFileStream
                    $server.Alter()
                }

                if ($Force -or $PSCmdlet.ShouldProcess($instance, "Need to restart Sql Service for change to take effect, continue?")) {
                    $RestartOutput = Restart-DbaService -ComputerName $server.ComputerNamePhysicalNetBIOS -InstanceName $server.InstanceName -Type Engine
                }
            } else {
                Write-Message -Level Verbose -Message "Skipping restart as old and new FileStream values are the same"
                $RestartOutput = [PSCustomObject]@{Status = 'No restart, as no change in values'}
            }
            [PsCustomObject]@{
                SqlInstance   = $server
                OriginalValue = $OutputLookup[$FileStreamState]
                NewValue      = $OutputLookup[$NewFileStream]
                RestartStatus = $RestartOutput.Status
            }
        }
    }
}
