#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Export-DbaSpConfigure {
    <#
        .SYNOPSIS
            Exports advanced sp_configure global configuration options to sql file.

        .DESCRIPTION
            Exports advanced sp_configure global configuration options to sql file.

        .PARAMETER SqlInstance
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2005 or higher.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Path
            Specifies the path to a file which will contain the sp_configure queries necessary to replicate the configuration settings on another instance. This file is suitable for input into Import-DbaSPConfigure.

    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    
        .NOTES
            Tags: SpConfig, Configure, Configuration
            Website: https://dbatools.io
            Author: Chrissy LeMaire (@cl), netnerds.net
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Export-DbaSpConfigure -SqlInstance sourceserver -Path C:\temp\sp_configure.sql

            Exports the SPConfigure settings on sourceserver to the file C:\temp\sp_configure.sql

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Path,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            if (-not (Test-Bound -ParameterName Path)) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $mydocs = [Environment]::GetFolderPath('MyDocuments')
                $path = "$mydocs\$($server.name.replace('\', '$'))-$timenow-sp_configure.sql"
            }
            
            try {
                Set-Content -Path $path "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE"
            }
            catch {
                Stop-Function -Message "Can't write to $path" -ErrorRecord $_ -Continue
            }
            
            $server.Configuration.ShowAdvancedOptions.ConfigValue = $true
            $server.Configuration.Alter($true)
            foreach ($sourceprop in $server.Configuration.Properties) {
                $displayname = $sourceprop.DisplayName
                $configvalue = $sourceprop.ConfigValue
                Add-Content -Path $path "EXEC sp_configure '$displayname' , $configvalue;"
            }
            Add-Content -Path $path "EXEC sp_configure 'show advanced options' , 0;"
            Add-Content -Path $Path "RECONFIGURE WITH OVERRIDE"
            $server.Configuration.ShowAdvancedOptions.ConfigValue = $false
            $server.Configuration.Alter($true)
            Get-ChildItem -Path $path
        }
    }
    
    end {
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
            Write-Message -Level Verbose -Message "Server configuration export finished"
        }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Export-SqlSpConfigure
    }
}
