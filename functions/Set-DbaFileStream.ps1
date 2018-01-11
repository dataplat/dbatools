function Set-DbaFileStream{
    <#
    .SYNOPSIS
        Sets the status of FileStream on specified SQL Server instances

    .DESCRIPTION
        Connects to the specified SQL Server instances, and sets the status of the FileStream feature to the required value

        To perform the action, the SQL Server instance must be restarted. By default we will prompt for confirmation for this action, this can be overridden with the -Force switch
    
    .PARAMETER SqlInstance
        The Sqlinstance to change. This may be an array of instances, or passed in from the pipeline. An array of dbatools connections may also be passed in

    .PARAMETER SqlCredential
        A sql credential to be used to connect to SqlInstance. If not specified the windows credentials of the calling session will be used

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
	
	.PARAMETER WhatIf
    	Shows what would happen if the cmdlet runs. The cmdlet is not run.

	.PARAMETER Confirm
	    Prompts you for confirmation before running the cmdlet.

    .EXAMPLE
        Set-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel T-Sql Only
        Set-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel 1
        
        These commands are functionally equivalent, both will set Filestream level on server1\instance2 to T-Sql Only
    
    .EXAMPLE
        Get-DbaFileStream -SqlInstance server1\instance2, server5\instance5 , prod\hr | Where-Object {$_.FileSteamStateID -gt 0} | Set-DbaFileStream -FileStreamLevel 0 -Force

        Using this pipeline you can scan a range of SQL instances and disable filestream on only those on which it's enabled

    .NOTES
        Tags:
        Author: Stuart Moore ( @napalmgram )

        dbatools PowerShell module (https://dbatools.io)
        Copyright (C) 2016 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName='piped')]
		[Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("0","1","2","Disabled","T-Sql Only","T-Sql and Win-32 Access")]
        [Object]$FileStreamLevel,
        [switch]$force,
		[switch][Alias('Silent')]$EnableException
    )
    BEGIN {
        if ($FileStreamLevel -notin ('0','1','2')){
            $NewFileStream = switch ($FileStreamLevel){
                "Disabled" {0}
                "T-Sql Only" {1}
                "T-Sql and Win-32 Access" {2}
            } 
        }
        else {
            $NewFileStream = $FileStreamLevel
        }
    }
    PROCESS {
        forEach ($instance in $SqlInstance) {
            if ($instance -isnot [string]){
                $instance = $instance.SqlInstance
            }
            try{
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch{
                Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $FileStreamState = [int]$server.Configuration.FilestreamAccessLevel.ConfigValue
            $OutputLookup = @{
                0='FileStream Disabled';
                1='FileStream Enabled for T-Sql Access';
                2='FileStream Enabled for T-Sql and Win-32 Access';
            }

            if ($FileStreamState -ne $NewFileStream) {
                if ($force -or $PSCmdlet.ShouldProcess($instance, "Changing from `"$($OutputLookup[$FileStreamState])`" to `"$($OutputLookup[$NewFileStream])`"")) {
                    $server.Configuration.FilestreamAccessLevel.ConfigValue = $NewFileStream
                    $server.alter()
                }
                    
                if ($force -or $PSCmdlet.ShouldProcess($instance, "Need to restart Sql Service for change to take effect, continue?")) {
                    $RestartOutput = Restart-DbaSqlService -ComputerName $server.ComputerNamePhysicalNetBIOS -InstanceName $server.InstanceName -Type Engine   
                }
            }
            else {
                Write-Message -Level Verbose -Message "Skipping restart as old and new FileStream values are the same"
                $RestartOutput = [PSCustomObject]@{Status = 'No restart, as no change in values'}
            }
            [PsCustomObject]@{
                SqlInstance = $server
                OriginalValue = $OutputLookup[$FileStreamState]
                NewValue = $OutputLookup[$NewFileStream]
                RestartStatus = $RestartOutput.Status
            } 

        }
    }
    END {}
}