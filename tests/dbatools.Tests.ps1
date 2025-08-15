Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$Path = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = (Get-Item $Path).Parent.FullName
$ModuleName = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -Replace ".Tests.ps1"
#$ManifestPath = "$ModulePath\$ModuleName.psd1"

Describe "$ModuleName Aliases" -Tag Aliases, Build {
    ## Get the Aliases that should -Be set from the psm1 file

    $psm1 = Get-Content $ModulePath\$ModuleName.psm1 -Verbose
    $Matches = [regex]::Matches($psm1, "AliasName`"\s=\s`"(\w*-\w*)`"")
    $Aliases = $Matches.ForEach{ $_.Groups[1].Value }

    foreach ($Alias in $Aliases) {
        Context "Testing $Alias Alias" {
            $Definition = (Get-Alias $Alias).Definition
            It "$Alias Alias should exist" {
                Get-Alias $Alias | Should Not BeNullOrEmpty
            }
            It "$Alias Aliased Command $Definition Should Exist" {
                Get-Command $Definition -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            }
        }
    }
}

function Split-ArrayInParts($array, [int]$parts) {
    #splits an array in "equal" parts
    $size = $array.Length / $parts
    $counter = [PSCustomObject] @{ Value = 0 }
    $groups = $array | Group-Object -Property { [math]::Floor($counter.Value++ / $size) }
    $rtn = @()
    foreach ($g in $groups) {
        $rtn += , @($g.Group)
    }
    $rtn
}


Describe "$ModuleName style" -Tag 'Compliance' {
    <#
    Ensures common formatting standards are applied:
    - OTBS style, courtesy of PSSA's Invoke-Formatter, is what dbatools uses
    - UTF8 without BOM is what is going to be used in PS Core, so we adopt this standard for dbatools
    #>
    $AllFiles = Get-ChildItem -Path $ModulePath -File -Recurse -Filter '*.ps*1' | Where-Object Name -ne 'dbatools.ps1'
    $AllFunctionFiles = Get-ChildItem -Path "$ModulePath\public", "$ModulePath\private\functions"-Filter '*.ps*1'
    Context "formatting" {
        $maxConcurrentJobs = $env:NUMBER_OF_PROCESSORS
        $whatever = Split-ArrayInParts -array $AllFunctionFiles -parts $maxConcurrentJobs
        $jobs = @()
        foreach ($piece in $whatever) {
            $jobs += Start-Job -ScriptBlock {
                foreach ($p in $Args) {
                    $content = Get-Content -Path $p.FullName -Raw -Encoding UTF8
                    $result = Invoke-Formatter -ScriptDefinition $content -Settings CodeFormattingOTBS
                    if ($result -ne $content) {
                        $p
                    }
                }
            } -ArgumentList $piece
        }
        $null = $jobs | Wait-Job #-Timeout 120
        $results = $jobs | Receive-Job

        foreach ($f in $results) {
            It "$f is not compliant with the OTBS formatting style. Please run Invoke-DbatoolsFormatter against the failing file and commit the changes." {
                1 | Should -Be 0
            }
        }
    }

    Context "BOM" {
        foreach ($f in $AllFiles) {
            [byte[]]$byteContent = Get-Content -Path $f.FullName -Encoding Byte -ReadCount 4 -TotalCount 4
            if ( $byteContent[0] -eq 0xef -and $byteContent[1] -eq 0xbb -and $byteContent[2] -eq 0xbf ) {
                It "$f has no BOM in it" {
                    "utf8bom" | Should -Be "utf8"
                }
            }
        }
    }


    Context "indentation" {
        foreach ($f in $AllFiles) {
            $LeadingTabs = Select-String -Path $f -Pattern '^[\t]+'
            if ($LeadingTabs.Count -gt 0) {
                It "$f is not indented with tabs (line(s) $($LeadingTabs.LineNumber -join ','))" {
                    $LeadingTabs.Count | Should -Be 0
                }
            }
            $TrailingSpaces = Select-String -Path $f -Pattern '([^ \t\r\n])[ \t]+$'
            if ($TrailingSpaces.Count -gt 0) {
                It "$f has no trailing spaces (line(s) $($TrailingSpaces.LineNumber -join ','))" {
                    $TrailingSpaces.Count | Should -Be 0
                }
            }
        }
    }
}


Describe "$ModuleName style" -Tag 'Compliance' {
    <#
    Ensures avoiding already discovered pitfalls
    #>
    $AllPublicFunctions = Get-ChildItem -Path "$ModulePath\public" -Filter '*.ps*1'

    Context "NoCompatibleTLS" {
        # .NET defaults clash with recent TLS hardening (e.g. no TLS 1.2 by default)
        foreach ($f in $AllPublicFunctions) {
            $NotAllowed = Select-String -Path $f -Pattern 'Invoke-WebRequest | New-Object System.Net.WebClient|\.DownloadFile'
            if ($NotAllowed.Count -gt 0 -and $f -notmatch 'DbaKbUpdate') {
                It "$f should instead use Invoke-TlsWebRequest, see #4250" {
                    $NotAllowed.Count | Should -Be 0
                }
            }
        }
    }
    Context "Shell.Application" {
        # Not every PS instance has Shell.Application
        foreach ($f in $AllPublicFunctions) {
            $NotAllowed = Select-String -Path $f -Pattern 'shell.application'
            if ($NotAllowed.Count -gt 0) {
                It "$f should not use Shell.Application (usually fallbacks for Expand-Archive, which dbatools ships), see #4800" {
                    $NotAllowed.Count | Should -Be 0
                }
            }
        }
    }

}


Describe "$ModuleName ScriptAnalyzerErrors" -Tag 'Compliance' {
    $ScriptAnalyzerErrors = @()
    $ScriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\public" -Severity Error
    $ScriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\private\functions" -Severity Error
    Context "Errors" {
        if ($ScriptAnalyzerErrors.Count -gt 0) {
            foreach ($err in $ScriptAnalyzerErrors) {
                It "$($err.scriptName) has Error(s) : $($err.RuleName)" {
                    $err.Message | Should -Be $null
                }
            }
        }
    }
}

Describe "$ModuleName Tests missing" -Tag 'Tests' {
    $functions = Get-ChildItem "$ModulePath\public\" -Recurse -Include *.ps1
    Context "Every function should have tests" {
        foreach ($f in $functions) {
            It "$($f.basename) has a tests.ps1 file" {
                Test-Path "$ModulePath\tests\$($f.basename).tests.ps1" | Should Be $true
            }
            If (Test-Path "$ModulePath\tests\$($f.basename).tests.ps1") {
                It "$($f.basename) has validate parameters unit test" {
                    $testFile = Get-Content "$ModulePath\tests\$($f.basename).Tests.ps1" -Raw
                    $hasValidation = $testFile -match 'Context "Validate parameters"' -or $testFile -match 'Context "Parameter validation"'
                    $hasValidation | Should -Be $true -Because "Test file must have parameter validation"
                }
            }
        }
    }
}

Describe "$ModuleName Function Name" -Tag 'Compliance' {
    $FunctionNameMatchesErrors = @()
    $FunctionNameDbaErrors = @()
    foreach ($item in (Get-ChildItem -Path "$ModulePath\public" -Filter '*.ps*1')) {
        $Tokens = $null
        $Errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$Tokens, [ref]$Errors)
        $FunctionName = $Ast.EndBlock.Statements.Name
        $BaseName = $item.BaseName
        if ($FunctionName -cne $BaseName) {
            $FunctionNameMatchesErrors += [PSCustomObject]@{
                FunctionName = $FunctionName
                BaseName     = $BaseName
                Message      = "$FunctionName is not equal to $BaseName"
            }
        }
        If ($FunctionName -NotMatch "-Dba") {
            $FunctionNameDbaErrors += [PSCustomObject]@{
                FunctionName = $FunctionName
                Message      = "$FunctionName does not contain -Dba"
            }

        }
    }
    foreach ($item in (Get-ChildItem -Path "$ModulePath\private\functions" -Filter '*.ps*1' | Where-Object BaseName -ne 'Where-DbaObject')) {
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$Tokens, [ref]$Errors)
        $FunctionName = $Ast.EndBlock.Statements.Name
        $BaseName = $item.BaseName
        if ($FunctionName -cne $BaseName) {
            Write-Host "aaa $functionname bbb $basename"
            $FunctionNameMatchesErrors += [PSCustomObject]@{
                FunctionName = $FunctionName
                BaseName     = $BaseName
                Message      = "$FunctionName is not equal to $BaseName"
            }
        }
    }
    Context "Function Name Matching Filename Errors" {
        if ($FunctionNameMatchesErrors.Count -gt 0) {
            foreach ($err in $FunctionNameMatchesErrors) {
                It "$($err.FunctionName) is not equal to $($err.BaseName)" {
                    $err.Message | Should -Be $null
                }
            }
        }
    }
    Context "Function Name has -Dba in it" {
        if ($FunctionNameDbaErrors.Count -gt 0) {
            foreach ($err in $FunctionNameDbaErrors) {
                It "$($err.FunctionName) does not contain -Dba" {
                    $err.Message | Should -Be $null
                }
            }
        }
    }
}

# test the module manifest - exports the right functions, processes the right formats, and is generally correct
<#
Describe "Manifest" {

    $Manifest = $null

    It "has a valid manifest" {

        {

            $script:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue

        } | Should Not Throw

    }
## Should -Be fixed now - Until the issue with requiring full paths for required assemblies is resolved need to keep this commented out RMS 01112016

$script:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
    It "has a valid name" {

        $script:Manifest.Name | Should -Be $ModuleName

    }



    It "has a valid root module" {

        $script:Manifest.RootModule | Should -Be "$ModuleName.psm1"

    }



    It "has a valid Description" {

        $script:Manifest.Description | Should -Be 'Provides extra functionality for SQL Server Database admins and enables SQL Server instance migrations.'

    }

    It "has a valid Author" {
        $script:Manifest.Author | Should -Be 'Chrissy LeMaire'
    }

    It "has a valid Company Name" {
        $script:Manifest.CompanyName | Should -Be 'dbatools.io'
    }
    It "has a valid guid" {

        $script:Manifest.Guid | Should -Be '9d139310-ce45-41ce-8e8b-d76335aa1789'

    }
    It "has valid PowerShell version" {
        $script:Manifest.PowerShellVersion | Should -Be '3.0'
    }

    It "has valid  required assemblies" {
        {$script:Manifest.RequiredAssemblies -eq @()} | Should -Be $true
    }

    It "has a valid copyright" {

        $script:Manifest.CopyRight | Should BeLike '* Chrissy LeMaire'

    }



 # Don't want this just yet

    It 'exports all public functions' {

        $FunctionFiles = Get-ChildItem "$ModulePath\public" -Filter *.ps1 | Select-Object -ExpandProperty BaseName

        $FunctionNames = $FunctionFiles

        $ExFunctions = $script:Manifest.ExportedFunctions.Values.Name
        $ExFunctions
        foreach ($FunctionName in $FunctionNames)

        {

            $ExFunctions -contains $FunctionName | Should -Be $true

        }

    }
}
#>