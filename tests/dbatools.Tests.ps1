#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools"
)
#$ManifestPath = "$ModulePath\$ModuleName.psd1"

Describe "$ModuleName Aliases" -Tag Aliases, Build {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
    }

    It "declared aliases and their target commands exist" {
        ## Get the Aliases that should -Be set from the psm1 file
        $psm1 = Get-Content "$ModulePath\$ModuleName.psm1"
        $aliasMatches = [regex]::Matches($psm1, "AliasName`"\s*=\s*`"(\w*-\w*)`"")
        $aliases = foreach ($aliasMatch in $aliasMatches) {
            $aliasMatch.Groups[1].Value
        }
        $aliasErrors = foreach ($alias in $aliases) {
            $aliasInfo = Get-Alias $alias -ErrorAction SilentlyContinue
            if (-not $aliasInfo) {
                "Alias $alias does not exist"
            } elseif (-not (Get-Command $aliasInfo.Definition -ErrorAction SilentlyContinue)) {
                "Alias $alias targets missing command $($aliasInfo.Definition)"
            }
        }

        $aliasErrors | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName style" -Tag Compliance {
    <#
    Ensures common formatting standards are applied:
    - OTBS style, courtesy of PSSA's Invoke-Formatter, is what dbatools uses
    - UTF8 without BOM is what is going to be used in PS Core, so we adopt this standard for dbatools
    #>
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $AllFiles = Get-ChildItem -Path $ModulePath -File -Recurse -Filter "*.ps*1" | Where-Object Name -ne "dbatools.ps1"
    }

    It "PowerShell files do not contain a UTF-8 BOM" {
        $bomFiles = foreach ($file in $AllFiles) {
            [byte[]]$byteContent = [System.IO.File]::ReadAllBytes($file.FullName)
            if ($byteContent.Length -gt 2 -and $byteContent[0] -eq 0xef -and $byteContent[1] -eq 0xbb -and $byteContent[2] -eq 0xbf) {
                $file.FullName
            }
        }

        $bomFiles | Should -BeNullOrEmpty
    }

    It "PowerShell files are not indented with tabs" {
        $leadingTabs = foreach ($file in $AllFiles) {
            foreach ($match in (Select-String -Path $file.FullName -Pattern "^[\t]+")) {
                "$($file.FullName):$($match.LineNumber)"
            }
        }

        $leadingTabs | Should -BeNullOrEmpty
    }

    It "PowerShell files do not contain trailing spaces" {
        $trailingSpaces = foreach ($file in $AllFiles) {
            foreach ($match in (Select-String -Path $file.FullName -Pattern "([^ \t\r\n])[ \t]+$")) {
                "$($file.FullName):$($match.LineNumber)"
            }
        }

        $trailingSpaces | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName prohibited APIs" -Tag Compliance {
    <#
    Ensures avoiding already discovered pitfalls
    #>
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $AllPublicFunctions = Get-ChildItem -Path "$ModulePath\public" -Filter "*.ps*1"
    }

    It "public commands use Invoke-TlsWebRequest for compatible TLS" {
        # .NET defaults clash with recent TLS hardening (e.g. no TLS 1.2 by default)
        $notCompatible = foreach ($file in $AllPublicFunctions) {
            $notAllowed = Select-String -Path $file.FullName -Pattern "Invoke-WebRequest | New-Object System.Net.WebClient|\.DownloadFile"
            if ($notAllowed.Count -gt 0 -and $file.Name -notmatch "DbaKbUpdate") {
                $file.FullName
            }
        }

        $notCompatible | Should -BeNullOrEmpty
    }

    It "public commands do not use Shell.Application" {
        # Not every PS instance has Shell.Application
        $shellApplicationFiles = foreach ($file in $AllPublicFunctions) {
            if (Select-String -Path $file.FullName -Pattern "shell.application") {
                $file.FullName
            }
        }

        $shellApplicationFiles | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName ScriptAnalyzerErrors" -Tag Compliance {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
    }

    It "public and private functions have no ScriptAnalyzer errors" {
        $scriptAnalyzerErrors = @()
        $scriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\public" -Severity Error
        $scriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\private\functions" -Severity Error
        # Copy-DbaCredential intentionally converts a decrypted migration value immediately back to SecureString for New-DbaCredential.
        $scriptAnalyzerErrors = $scriptAnalyzerErrors | Where-Object {
            -not ($PSItem.RuleName -eq "PSAvoidUsingConvertToSecureStringWithPlainText" -and $PSItem.ScriptName -eq "Copy-DbaCredential.ps1")
        }

        $scriptAnalyzerErrors | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName Tests missing" -Tag Tests {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $functions = Get-ChildItem "$ModulePath\public\" -Recurse -Include "*.ps1"
    }

    It "every public function has a test file" {
        $missingTests = foreach ($file in $functions) {
            if (-not (Test-Path "$ModulePath\tests\$($file.BaseName).Tests.ps1")) {
                $file.BaseName
            }
        }

        $missingTests | Should -BeNullOrEmpty
    }

    It "every public function test has parameter validation" {
        $missingValidation = foreach ($file in $functions) {
            $testPath = "$ModulePath\tests\$($file.BaseName).Tests.ps1"
            if (Test-Path $testPath) {
                $testFile = Get-Content $testPath -Raw
                $hasValidation = $testFile -match "Context `"Validate parameters`"" -or $testFile -match "Context `"Parameter validation`""
                if (-not $hasValidation) {
                    $file.BaseName
                }
            }
        }

        $missingValidation | Should -BeNullOrEmpty
    }
}

Describe "$ModuleName Function Name" -Tag Compliance {
    BeforeAll {
        $ModulePath = Split-Path $PSScriptRoot -Parent
        $publicFunctions = Get-ChildItem -Path "$ModulePath\public" -Filter "*.ps*1"
        $privateFunctions = Get-ChildItem -Path "$ModulePath\private\functions" -Filter "*.ps*1" | Where-Object BaseName -ne "Where-DbaObject"
    }

    It "function names match their filenames" {
        $functionNameMatchesErrors = foreach ($item in @($publicFunctions) + @($privateFunctions)) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$tokens, [ref]$errors)
            $functionName = $ast.EndBlock.Statements.Name
            if ($functionName -cne $item.BaseName) {
                "$functionName is not equal to $($item.BaseName)"
            }
        }

        $functionNameMatchesErrors | Should -BeNullOrEmpty
    }

    It "public function names contain -Dba" {
        $functionNameDbaErrors = foreach ($item in $publicFunctions) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$tokens, [ref]$errors)
            $functionName = $ast.EndBlock.Statements.Name
            if ($functionName -notmatch "-Dba") {
                $functionName
            }
        }

        $functionNameDbaErrors | Should -BeNullOrEmpty
    }
}

# test the module manifest - exports the right functions, processes the right formats, and is generally correct
<#
Describe "Manifest" {

    $global:Manifest = $null

    It "has a valid manifest" {

        {

            $global:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue

        } | Should -Not -Throw

    }
## Should -Be fixed now - Until the issue with requiring full paths for required assemblies is resolved need to keep this commented out RMS 01112016

$global:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
    It "has a valid name" {

        $global:Manifest.Name | Should -Be $ModuleName

    }



    It "has a valid root module" {

        $global:Manifest.RootModule | Should -Be "$ModuleName.psm1"

    }



    It "has a valid Description" {

        $global:Manifest.Description | Should -Be 'Provides extra functionality for SQL Server Database admins and enables SQL Server instance migrations.'

    }

    It "has a valid Author" {
        $global:Manifest.Author | Should -Be 'Chrissy LeMaire'
    }

    It "has a valid Company Name" {
        $global:Manifest.CompanyName | Should -Be 'dbatools.io'
    }
    It "has a valid guid" {

        $global:Manifest.Guid | Should -Be '9d139310-ce45-41ce-8e8b-d76335aa1789'

    }
    It "has valid PowerShell version" {
        $global:Manifest.PowerShellVersion | Should -Be '3.0'
    }

    It "has valid  required assemblies" {
        $global:Manifest.RequiredAssemblies | Should -BeEmpty
    }

    It "has a valid copyright" {

        $global:Manifest.CopyRight | Should -BeLike '* Chrissy LeMaire'

    }



 # Don't want this just yet

    It 'exports all public functions' {

        $FunctionFiles = Get-ChildItem "$ModulePath\public" -Filter *.ps1 | Select-Object -ExpandProperty BaseName

        $FunctionNames = $FunctionFiles

        $ExFunctions = $global:Manifest.ExportedFunctions.Values.Name
        $ExFunctions
        foreach ($FunctionName in $FunctionNames)

        {

            $ExFunctions -contains $FunctionName | Should -Be $true

        }

    }
}
#>
