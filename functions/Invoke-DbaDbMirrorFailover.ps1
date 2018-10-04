#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Invoke-DbaDbMirrorFailover {
    <#
        .SYNOPSIS
            Failover a mirrored database

        .DESCRIPTION
            Failover a mirrored database

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the primary SQL Server.

        .PARAMETER SqlCredential
            Login to the primary instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            The database or databases to mirror

        .PARAMETER InputObject
            Allows piping from Get-DbaDatabase

        .PARAMETER Force
            Force Failover and allow data loss
    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Mirror, HA
            Author: Chrissy LeMaire (@cl), netnerds.net
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2018 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT
            
            TODO: add service accounts

        .LINK
            https://dbatools.io/Invoke-DbaDbMirrorFailover

        .EXAMPLE
            $params = @{
                    Primary = 'sql2017a'
                    Mirror = 'sql2017b'
                    MirrorSqlCredential = 'sqladmin'
                    Witness = 'sql2019'
                    Database = 'onthewall'
                    NetworkShare = '\\nas\sql\share'
                }
    
            Invoke-DbaDbMirrorFailover @params
        
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        
        $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        
        foreach ($db in $InputObject) {
            # if it's async, you have to break the mirroring and allow data loss
            # alter database set partner force_service_allow_data_loss
            # if it's sync mirroring you know it's all in sync, so you can just do alter database [dbname] set partner failover
            
            if ($Force) {
                $db | Set-DbaDbMirror -State ForceFailoverAndAllowDataLoss
            }
            else {
                $db | Set-DbaDbMirror -SafetyLevel Full
                $db | Set-DbaDbMirror -State Failover
            }
        }
    }
}