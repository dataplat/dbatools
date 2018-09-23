#ValidationTags#CodeStyle,Messaging,FlowControl,Pipeline#
function Install-DbaSQLWATCH{
    <#
        .SYNOPSIS
            Installs or updates SQLWATCH.

        .DESCRIPTION
            Downloads, extracts and installs or updates SQLWATCH.
            https://sqlwatch.io/

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database to install SQLWATCH into.

        .PARAMETER Branch
            Specifies an alternate branch of SQLWATCH to install. (master or dev)

        .PARAMETER LocalFile
            Specifies the path to a local file to install SQLWATCH from. This *should* be the zipfile as distributed by the maintainers.
            If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/marcingminski/sqlwatch

        .PARAMETER Force
            If this switch is enabled, SQLWATCH will be downloaded from the internet even if previously cached.

        .PARAMETER Confirm
            Prompts to confirm actions

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SQLWATCH, marcingminski
            Author: marcingminski ()
            Website: https://sqlwatch.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Install-DbaSQLWATCH

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance server1 -Database master

            Logs into server1 with Windows authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance server1\instance1 -Database DBA

            Logs into server1\instance1 with Windows authentication and then installs SQLWATCH in the DBA database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance server1\instance1 -Database master -SqlCredential $cred

            Logs into server1\instance1 with SQL authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

            Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
            $servers | Install-DbaSQLWATCH

            Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs SQLWATCH in the master database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance sql2016 -Branch development

            Installs the dev branch version of SQLWATCH in the master database on sql2016 instance.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('master', 'development')]
        [string]$Branch = "master",
        [object]$Database = "master",
        [string]$LocalFile,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        $DbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

        $url = "https://github.com/marcingminski/sqlwatch/archive/$Branch.zip"

        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $zipfile = "$temp\SQLWATCH-$Branch.zip"
        $zipfolder = "$temp\SQLWATCH-$Branch\"
        $sqwLocation = "SQLWATCH_$Branch"
        $LocalCachedCopy = Join-Path -Path $DbatoolsData -ChildPath $sqwLocation
        if ($LocalFile) {
            if (-not(Test-Path $LocalFile)) {
                Stop-Function -Message "$LocalFile doesn't exist"
                return
            }
            if (-not($LocalFile.EndsWith('.zip'))) {
                Stop-Function -Message "$LocalFile should be a zip file"
                return
            }
        }

        if ($Force -or -not(Test-Path -Path $LocalCachedCopy -PathType Container) -or $LocalFile) {
            # Force was passed, or we don't have a local copy, or $LocalFile was passed
            if ($zipfile | Test-Path) {
                Remove-Item -Path $zipfile -ErrorAction SilentlyContinue
            }
            if ($zipfolder | Test-Path) {
                Remove-Item -Path $zipfolder -Recurse -ErrorAction SilentlyContinue
            }

            $null = New-Item -ItemType Directory -Path $zipfolder -ErrorAction SilentlyContinue
            if ($LocalFile) {
                Unblock-File $LocalFile -ErrorAction SilentlyContinue
                Expand-Archive -Path $LocalFile -DestinationPath $zipfolder -Force
            }
            else {
                Write-Message -Level Verbose -Message "Downloading and unzipping the SQLWATCH zip file."

                try {
                    $oldSslSettings = [System.Net.ServicePointManager]::SecurityProtocol
                    [System.Net.ServicePointManager]::SecurityProtocol = "Tls12"
                    try {
                        $wc = New-Object System.Net.WebClient
                        $wc.DownloadFile($url, $zipfile)
                    }
                    catch {
                        # Try with default proxy and usersettings
                        $wc = New-Object System.Net.WebClient
                        $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        $wc.DownloadFile($url, $zipfile)
                    }
                    [System.Net.ServicePointManager]::SecurityProtocol = $oldSslSettings

                    # Unblock if there's a block
                    Unblock-File $zipfile -ErrorAction SilentlyContinue

                    Expand-Archive -Path $zipfile -DestinationPath $zipfolder -Force

                    Remove-Item -Path $zipfile
                }
                catch {
                    Stop-Function -Message "Couldn't download SQLWATCH. Download and install manually from https://github.com/marcingminski/sqlwatch/archive/$Branch.zip." -ErrorRecord $_
                    return
                }
            }

            ## Copy it into local area
            if (Test-Path -Path $LocalCachedCopy -PathType Container) {
                Remove-Item -Path (Join-Path $LocalCachedCopy '*') -Recurse -ErrorAction SilentlyContinue
            }
            else {
                $null = New-Item -Path $LocalCachedCopy -ItemType Container
            }
            Copy-Item -Path $zipfolder -Destination $LocalCachedCopy -Recurse
        }
    }


    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Starting installing/updating SQLWATCH in $database on $instance."

            try {

                # create a publish profile and publish DACPAC
                $DacPacPath = Get-ChildItem -Filter "SQLWATCH.dacpac" -Path $LocalCachedCopy -Recurse | Select-Object -ExpandProperty FullName
                $PublishOptions = @{
                    RegisterDataTierApplication = $true
                }
                $DacProfile = New-DbaDacProfile -SqlInstance $server -Database $Database -Path $LocalCachedCopy -PublishOptions $PublishOptions | Select-Object -ExpandProperty FileName
                $PublishResults = Publish-DbaDacPackage -SqlInstance $server -Database $Database -Path $DacPacPath -PublishXml $DacProfile
                
                # parse results
                $parens = Select-String -InputObject $PublishResults.Result -Pattern "\(([^\)]+)\)" -AllMatches
                if ($parens.matches) {
                    $ExtractedResult = $parens.matches | select -Last 1 | %{ $_.value }
                }                
                $result = [PSCustomObject]@{
                    ComputerName = $PublishResults.ComputerName
                    InstanceName = $PublishResults.InstanceName
                    SqlInstance = $PublishResults.SqlInstance
                    Database = $PublishResults.Database
                    Dacpac = $PublishResults.Dacpac
                    PublishXml = $PublishResults.PublishXml
                    Result = $ExtractedResult
                    FullResult = $PublishResults.Result
                    DeployOptions = $PublishResults.DeployOptions
                    SqlCmdVariableValues = $PublishResults.SqlCmdVariableValues
                }
                Select-DefaultView -InputObject $result -ExcludeProperty Dacpac,PublishXml,FullResult,DeployOptions,SqlCmdVariableValues
            }
            catch {
                Stop-Function -Message "DACPAC failed to publish to $database on $instance." -ErrorRecord $_ -Target $instance -Continue
            }

            Write-PSFMessage -Level Verbose -Message "Finished installing/updating SQLWATCH in $database on $instance."
            #notify user of location to PowerBI file
            $pbitLocation = Get-ChildItem $LocalCachedCopy -Recurse -include *.pbit | Select-Object -ExpandProperty Directory -Unique
            Write-PSFMessage -Level Host -Message "SQLWATCH installed successfully. Power BI dashboard files can be found at $($pbitLocation.FullName)"
        }
    }

    end {}
}