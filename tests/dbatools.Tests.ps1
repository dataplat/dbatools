Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$Path = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = (get-item $Path ).parent.FullName
$ModuleName = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -Replace ".Tests.ps1"
#$ManifestPath = "$ModulePath\$ModuleName.psd1"

Describe 'dbatools module test' -Tag 'Compliance' {
    Context 'Doing something awesome' {
        It 'It should have tests' {
            $true | Should be $true
        }
    }
}


Describe "$ModuleName Aliases" -tag Build , Aliases {
    ## Get the Aliases that should be set from the psm1 file

    $psm1 = Get-Content $ModulePath\$ModuleName.psm1 -Verbose
    $Matches = [regex]::Matches($psm1, "AliasName`"\s=\s`"(\w*-\w*)`"")
    $Aliases = $Matches.ForEach{$_.Groups[1].Value}

    foreach ($Alias in $Aliases) {
        Context "Testing $Alias Alias" {
            $Definition = (Get-Alias $Alias).Definition
            It "$Alias Alias should exist" {
                Get-Alias $Alias| Should Not BeNullOrEmpty
            }
            It "$Alias Aliased Command $Definition Should Exist" {
                Get-Command $Definition -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
            }
        }
    }
}

Describe "$ModuleName indentation" -Tag 'Compliance' {
    $AllFiles = Get-ChildItem -Path $ModulePath -File -Recurse  -Filter '*.ps*1'

    foreach ($f in $AllFiles) {
        $LeadingTabs = Select-String -Path $f -Pattern '^[\t]+'
        if ($LeadingTabs.Count -gt 0) {
            It "$f is not indented with tabs (line(s) $($LeadingTabs.LineNumber -join ','))" {
                $LeadingTabs.Count | Should Be 0
            }
        }
        $TrailingSpaces = Select-String -Path $f -Pattern '([^ \t\r\n])[ \t]+$'
        if ($TrailingSpaces.Count -gt 0) {
            It "$f has no trailing spaces (line(s) $($TrailingSpaces.LineNumber -join ','))" {
                $TrailingSpaces.Count | Should Be 0
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

            $Script:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue

        } | Should Not Throw

    }
## Should be fixed now - Until the issue with requiring full paths for required assemblies is resolved need to keep this commented out RMS 01112016

$Script:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
    It "has a valid name" {

        $Script:Manifest.Name | Should Be $ModuleName

    }



    It "has a valid root module" {

        $Script:Manifest.RootModule | Should Be "$ModuleName.psm1"

    }



    It "has a valid Description" {

        $Script:Manifest.Description | Should Be 'Provides extra functionality for SQL Server Database admins and enables SQL Server instance migrations.'

    }

    It "has a valid Author" {
        $Script:Manifest.Author | Should Be 'Chrissy LeMaire'
    }

    It "has a valid Company Name" {
        $Script:Manifest.CompanyName | Should Be 'dbatools.io'
    }
    It "has a valid guid" {

        $Script:Manifest.Guid | Should Be '9d139310-ce45-41ce-8e8b-d76335aa1789'

    }
    It "has valid PowerShell version" {
        $Script:Manifest.PowerShellVersion | Should Be '3.0'
    }

    It "has valid  required assemblies" {
        {$Script:Manifest.RequiredAssemblies -eq @()} | Should Be $true
    }

    It "has a valid copyright" {

        $Script:Manifest.CopyRight | Should BeLike '* Chrissy LeMaire'

    }



 # Don't want this just yet

    It 'exports all public functions' {

        $FunctionFiles = Get-ChildItem "$ModulePath\functions" -Filter *.ps1 | Select-Object -ExpandProperty BaseName

        $FunctionNames = $FunctionFiles

        $ExFunctions = $Script:Manifest.ExportedFunctions.Values.Name
        $ExFunctions
        foreach ($FunctionName in $FunctionNames)

        {

            $ExFunctions -contains $FunctionName | Should Be $true

        }

    }
}
#>