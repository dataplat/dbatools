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

        .PARAMETER Whatif
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Export-DbaSpConfigure -SqlInstance sourceserver -Path C:\temp\sp_configure.sql

            Exports the SPConfigure settings on sourceserver to the file C:\temp\sp_configure.sql

        .OUTPUTS
            File to disk, and string path.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [string]$Path,
        [PSCredential]$SqlCredential
    )

    begin {
        $server = Connect-SqlInstance $sqlinstance $SqlCredential

        if ($server.versionMajor -lt 9) {
            Write-Error "Windows 2000 is not supported for sp_configure export."
            break
        }

        if ($path.length -eq 0) {
            $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
            $mydocs = [Environment]::GetFolderPath('MyDocuments')
            $path = "$mydocs\$($server.name.replace('\', '$'))-$timenow-sp_configure.sql"
        }

    }

    process {
        try {
            Set-Content -Path $path "EXEC sp_configure 'show advanced options' , 1;  RECONFIGURE WITH OVERRIDE"
        }
        catch {
            throw "Can't write to $path"
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
        return $path
    }

    end {
        $server.ConnectionContext.Disconnect()

        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
            Write-Output "Server configuration export finished"
        }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Export-SqlSpConfigure
    }
}
