function Get-DbaFileStream{
    <#
    .SYNOPSIS
        Returns the status of FileStream on specified SQL Server instances

    .DESCRIPTION
        Connects to the specified SQL Server instances, and returns the status of the FileStream feature

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
    param(
        [parameter(ValueFromPipeline = $true, Position = 1)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
		[switch][Alias('Silent')]$EnableException
    )
    BEGIN {}
    PROCESS {
        forEach ($instance in $SqlInstance) {
            try{
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch{
                Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $FileStreamState = $server.Configuration.FilestreamAccessLevel
            $OutputText = switch ($FileStreamState.RunValue){
                0 {'FileStream Disabled'}
                1 {'FileStream Enabled for T-Sql Access'}
                2 {'FileStream Enabled for T-Sql and Win-32 Access'}
                3 {'FileStream Enabled for T-Sql, Win32 and remote Access'}
            }
            [PsCustomObject]@{
                SqlInstance = $server
                FileStreamState = $OutputText
                FileSteamStatID = $FileStreamState.RunValue
                FileStreamConfig = $FileStreamState
            } | Select-DefaultView -Exclude FileStreamConfig
        }
    }
    END {}
}