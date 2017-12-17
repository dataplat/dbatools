function Set-DbaFileStream{
    <#
    .SYNOPSIS
        Stes the status of FileStream on specified SQL Server instances

    .DESCRIPTION
        Connects to the specified SQL Server instances, and sets the status of the FileStream feature to the required value

    .PARAMETER SqlInstance
        The Sqlinstance to query. This may be an array of instances, or passed in from the pipeline. And array of dbatools connections may also be passed in

    .PARAMETER SqlCredential
        A sql credential to be used to connect to SqlInstance. If not specified the windows credentials of the calling session will be used

    .EXAMPLE
        Get-DbaFileStream -SqlInstance server1\instance2 

        Will return wether FileStream is enabled on the server1\instance2 instance

    .NOTES
        Tags:
        Author: Stuart Moore ( @napalmgram )

        dbatools PowerShell module (https://dbatools.io)
        Copyright (C) 2016 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [parameter(ValueFromPipeline = $true, Position = 1)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("0","1","2","3","Disable","T-Sql Only","T-Sql and Win-32 Access", "Remote T-Sql and Win-32 Access")]
        [Object]$FileStreamLevel,
        [switch]$force,
		[switch][Alias('Silent')]$EnableException
    )
    BEGIN {
        if ($FileStreamLevel -notin ('0','1','2','3')){
            $NewFs = switch ($FileStreamLevel){
                "Disable" {0}
                "T-Sql Only" {1}
                "T-Sql and Win-32 Access" {2}
                "Remote T-Sql and Win-32 Access" {3}
            } 
        }
        else {
            $NewFs = $FileStreamLevel
        }
    }
    PROCESS {
        forEach ($instance in $SqlInstance) {
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
                3='FileStream Enabled for T-Sql, Win32 and remote Access'
            }

            if ($force -or $PSCmdlet.ShouldProcess($instance, "Changing from `"$($OutputLookup[$FileStreamState.ConfigValue])`" to `"$($OutputLookup[$NewFs])`"")) {
                $server.Configuration.FilestreamAccessLevel.ConfigValue = $NewFs
            }
                
            if ($force -or $PSCmdlet.ShouldProcess($instance, "Need to restart Sql Service for change to take effect, continue?")) {
                $RestartOutput = Restart-DbaSqlService -ComputerName $server.ComputerNamePhysicalNetBIOS -InstanceName $server.InstanceName -Type Engine   
            }

            [PsCustomObject]@{
                SqlInstance = $server
                OriginalValue = $OutputLookup[$FileStreamState]
                NewValue = $OutputLookup[$NewFs]
                RestartStatus = $RestartOutput.Status
            } | Select-DefaultView -Exclude FileStreamConfig
        }
    }
    END {}
}