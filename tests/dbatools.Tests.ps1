$Path = Split-Path -Parent $MyInvocation.MyCommand.Path 
$ModulePath = (get-item $Path ).parent.FullName 
$ModuleName = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -Replace ".Tests.ps1" 
$ManifestPath   = "$ModulePath\$ModuleName.psd1" 


# test the module manifest - exports the right functions, processes the right formats, and is generally correct

Describe "Manifest" {

    $Manifest = $null
<#
    It "has a valid manifest" {

        {

            $Script:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue

        } | Should Not Throw

    }
#> ## Until the issue with requiring full paths for required assemblies is resolved need to keep this commented out RMS 01112016

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

	It "has a valid AUthor" {
		$Script:Manifest.Author | SHould Be 'Chrissy LeMaire'
	}

	It "has a valid Company Namne" {
		$Script:Manifest.CompanyName | Should Be 'dbatools.io'
	}
    It "has a valid guid" {

        $Script:Manifest.Guid | Should Be '9d139310-ce45-41ce-8e8b-d76335aa1789'

    }
	It "has valid PowerShell version" {
		$Script:Manifest.PowerShellVersion | Should Be '3.0'
	}

	It "has valid (invalid!!) required assemblies" {
		$Script:Manifest.RequiredAssemblies | Should Be 'Microsoft.SqlServer.Smo','Microsoft.SqlServer.SmoExtended'
	}

	It "has a valid copyright" {

		$Script:Manifest.CopyRight | Should Be '2016 Chrissy LeMaire'

	}



	It 'exports all public functions' {

		$FunctionFiles = Get-ChildItem "$ModulePath\functions" -Filter *.ps1 -Exclude 'dynamicparams.ps1','sharedfunctions.ps1','Template.ps1'| Select -ExpandProperty BaseName

		$FunctionNames = $FunctionFiles

		$ExFunctions = $Script:Manifest.ExportedFunctions.Values.Name
		$ExFunctions
		foreach ($FunctionName in $FunctionNames)

		{

			$ExFunctions -contains $FunctionName | Should Be $true

		}

	}

}

