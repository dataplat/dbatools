function Get-DbaSqlBuildReference {
    <#
    .SYNOPSIS
        Returns SQL Server Build infos on a SQL instance

    .DESCRIPTION
        Returns info about the specific build of a SQL instance, including the SP, the CU and the reference KB, wherever possible.
        It also includes End Of Support dates as specified on Microsoft Lifecycle Policy

    .PARAMETER Build
        Instead of connecting to a real instance, pass a string identifying the build to get the info back.

    .PARAMETER SqlInstance
        Target any number of instances, in order to return their build state.

    .PARAMETER SqlCredential
        When connecting to an instance, use the credentials specified.

    .PARAMETER Update
        Looks online for the most up to date reference, replacing the local one.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        Get-DbaSqlBuildReference -Build "12.00.4502"

        Returns information about a build identified by  "12.00.4502" (which is SQL 2014 with SP1 and CU11)

    .EXAMPLE
        Get-DbaSqlBuildReference -Build "12.00.4502" -Update

        Returns information about a build trying to fetch the most up to date index online. When the online version is newer, the local one gets overwritten

    .EXAMPLE
        Get-DbaSqlBuildReference -Build "12.0.4502","10.50.4260"

        Returns information builds identified by these versions strings

    .EXAMPLE
        Get-DbaRegisteredServer -SqlInstance sqlserver2014a | Get-DbaSqlBuildReference

        Integrate with other commandlets to have builds checked for all your registered servers on sqlserver2014a

    .NOTES
        Author: niphlod
        Editor: Fred
        Tags: SqlBuild

        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSqlBuildReference
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    Param (
        [version[]]
        $Build,

        [parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]
        $SqlInstance,

        [Alias("Credential")]
        [PsCredential]
        $SqlCredential,

        [switch]
        $Update,

        [switch]
        [Alias('Silent')]$EnableException
    )

    begin {
        #region Helper functions
        function Get-DbaSqlBuildReferenceIndex {
            [CmdletBinding()]
            Param (
                [string]
                $Moduledirectory,

                [bool]
                $Update,

                [bool]
                $EnableException
            )

            $orig_idxfile = "$Moduledirectory\bin\dbatools-buildref-index.json"
            $DbatoolsData = Get-DbaConfigValue -Name 'Path.DbatoolsData'
            $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"

            if (-not (Test-Path $orig_idxfile)) {
                Write-Message -Level Warning -EnableException $EnableException -Message "Unable to read local SQL build reference file. Check your module integrity!"
            }

            if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
                throw "Build reference file not found, check module health!"
            }

            # If no writable copy exists, create one and return the module original
            if (-not (Test-Path $writable_idxfile)) {
                Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                $result = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
            }

            # Else, if both exist, update the writeable if necessary and return the current version
            elseif (Test-Path $orig_idxfile) {
                $module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
                $data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json

                $module_time = Get-Date $module_content.LastUpdated
                $data_time = Get-Date $data_content.LastUpdated

                $offline_time = $module_time
                if ($module_time -gt $data_time) {
                    Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                    $result = $module_content
                }
                else {
                    $result = $data_content
                    $offline_time = $data_time
                }
                # If Update is passed, try to fetch from online resource and store into the writeable
                if ($Update) {
                    $WebContent = Get-DbaSqlBuildReferenceIndexOnline -EnableException $EnableException
                    if ($null -ne $WebContent) {
                        $webdata_content = $WebContent.Content | ConvertFrom-Json
                        $webdata_time = Get-Date $webdata_content.LastUpdated
                        if ($webdata_time -gt $offline_time) {
                            Write-Message -Level Output -Message "Index updated correctly, last update on: $(Get-Date -Date $webdata_time -Format s), was $(Get-Date -Date $offline_time -Format s)"
                            $WebContent.Content | Out-File $writable_idxfile -Encoding utf8 -ErrorAction Stop
                            $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
                        }
                    }
                }
            }

            # Else if the module version of the file no longer exists, but the writable version exists, return the writable version
            else {
                $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
            }

            $LastUpdated = Get-Date -Date $result.LastUpdated
            if ($LastUpdated -lt (Get-Date).AddDays(-45)) {
                Write-Message -Level Warning -EnableException $EnableException -Message "Index is stale, last update on: $(Get-Date -Date $LastUpdated -Format s), try the -Update parameter to fetch the most up to date index"
            }

            $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
        }

        function Get-DbaSqlBuildReferenceIndexOnline {
            [CmdletBinding()]
            Param (
                [bool]
                $EnableException
            )
            $url = Get-DbaConfigValue -Name 'assets.sqlbuildreference'
            try {
                $WebContent = Invoke-WebRequest $url -ErrorAction Stop
            }
            catch {
                try {
                    Write-Message -Level Verbose -EnableException $EnableException -Message "Probably using a proxy for internet access, trying default proxy settings"
                    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                    $WebContent = Invoke-WebRequest $url -ErrorAction Stop
                }
                catch {
                    Write-Message -Level Warning -EnableException $EnableException -Message "Couldn't download updated index from $url"
                    return
                }
            }
            return $WebContent
        }

        function Resolve-DbaSqlBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            Param (
                [version]
                $Build,

                $Data,

                [bool]
                $EnableException
            )

            Write-Message -Level Verbose -EnableException $EnableException -Message "Looking for $Build"

            $IdxVersion = $Data | Where-Object Version -like "$($Build.Major).$($Build.Minor).*"
            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            Write-Message -Level Verbose -EnableException $EnableException -Message "We have $($IdxVersion.Length) builds in store for this Release"
            If ($IdxVersion.Length -eq 0) {
                Write-Message -Level Warning -EnableException $EnableException -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            }
            else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -date $el.SupportedUntil)
                }
                $Detected.KB = $el.KBList
                if ($el.Version -eq $Build) {
                    $Detected.MatchType = 'Exact'
                    break
                }
            }
            return $Detected
        }
        #endregion Helper functions

        $moduledirectory = $MyInvocation.MyCommand.Module.ModuleBase

        try {
            $IdxRef = Get-DbaSqlBuildReferenceIndex -Moduledirectory $moduledirectory -Update $Update -EnableException $EnableException
        }
        catch {
            Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            #region Ensure the connection is established
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $null = $server.Version.ToString()
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            #endregion Ensure the connection is established

            $Detected = Resolve-DbaSqlBuild -Build $server.Version -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $server.DomainInstanceName
                Build          = $server.Version
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            }
        }

        foreach ($buildstr in $Build) {
            $Detected = Resolve-DbaSqlBuild -Build $buildstr -Data $IdxRef -EnableException $EnableException

            [PSCustomObject]@{
                SqlInstance    = $null
                Build          = $buildstr
                NameLevel      = $Detected.Name
                SPLevel        = $Detected.SP
                CULevel        = $Detected.CU
                KBLevel        = $Detected.KB
                SupportedUntil = $Detected.SupportedUntil
                MatchType      = $Detected.MatchType
                Warning        = $Detected.Warning
            } | Select-DefaultView -ExcludeProperty SqlInstance
        }
    }
}
