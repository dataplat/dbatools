#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Select-DefaultView",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# migration PHASE-0-TRACKER row P0-009 - the ps1xml round-trip proof for OutputHelper.
#
# OutputHelper (project/dbatools/Utility/OutputHelper.cs) is the compiled Select-DefaultView
# equivalent every ported cmdlet shapes output through. Its MSTest coverage proves the ETS
# decoration is attached correctly; this proof closes the other half the row asks for - that a
# decorated object RENDERS through the shipped Types/Format data (xml/dbatools.Format.ps1xml)
# identically to the PowerShell Select-DefaultView function.
#
# Two independent round trips, both on the real formatting engine with the module (and thus its
# ps1xml) imported:
#   1. InsertTypeName drives the shipped Format.ps1xml view. Inserting "dbatools.MigrationObject"
#      selects the <View> in xml/dbatools.Format.ps1xml (columns Type/Name/Status/Notes), so the
#      curated columns come from the SHIPPED format data, not from a runtime display set.
#   2. SetDefaultDisplayPropertySet renders identically to Select-DefaultView -Property for a type
#      with no ps1xml view, where PSStandardMembers alone drives the default columns.

Describe "OutputHelper ps1xml round-trip (P0-009)" -Tag IntegrationTests {
    Context "InsertTypeName renders through the shipped dbatools.Format.ps1xml view" {
        BeforeAll {
            # Properties Type/Name/Status/Notes match the shipped dbatools.MigrationObject view;
            # SecretColumn is deliberately outside it and must not render.
            $migObject = [pscustomobject]@{
                Type         = "Database"
                Name         = "WideWorldImporters"
                Status       = "Successful"
                Notes        = "copied-clean"
                SecretColumn = "must-not-render"
            }
            [Dataplat.Dbatools.Utility.OutputHelper]::InsertTypeName($migObject, "MigrationObject")

            $psMigObject = [pscustomobject]@{
                Type         = "Database"
                Name         = "WideWorldImporters"
                Status       = "Successful"
                Notes        = "copied-clean"
                SecretColumn = "must-not-render"
            } | Select-DefaultView -Property Type, Name, Status, Notes -TypeName MigrationObject

            $csRender = ($migObject | Format-Table | Out-String).Trim()
            $psRender = ($psMigObject | Format-Table | Out-String).Trim()
        }

        It "inserts the dbatools-prefixed type name the shipped view is keyed on" {
            $migObject.PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "confirms the shipped Format.ps1xml view is actually loaded for that type" {
            (Get-FormatData -TypeName "dbatools.MigrationObject" -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }

        It "renders the view's curated columns from the shipped format data" {
            $csRender | Should -Match "Type"
            $csRender | Should -Match "Name"
            $csRender | Should -Match "Status"
            $csRender | Should -Match "Notes"
            $csRender | Should -Match "WideWorldImporters"
        }

        It "omits the property that lies outside the shipped view" {
            $csRender | Should -Not -Match "SecretColumn"
            $csRender | Should -Not -Match "must-not-render"
        }

        It "renders identically to the Select-DefaultView-decorated object" {
            $csRender | Should -Be $psRender
        }
    }

    Context "SetDefaultDisplayPropertySet renders identically to Select-DefaultView -Property" {
        BeforeAll {
            # dbatools.P0009RoundTrip has no ps1xml view, so PSStandardMembers alone drives the
            # default columns - the pure Select-DefaultView -Property parity path.
            $csObject = [pscustomobject]@{ Alpha = 1; Beta = 2; Gamma = 3; Delta = 4 }
            [Dataplat.Dbatools.Utility.OutputHelper]::SetDefaultDisplayPropertySet($csObject, [string[]]@("Alpha", "Beta"))
            [Dataplat.Dbatools.Utility.OutputHelper]::InsertTypeName($csObject, "P0009RoundTrip")

            $psObject = [pscustomobject]@{ Alpha = 1; Beta = 2; Gamma = 3; Delta = 4 } |
                Select-DefaultView -Property Alpha, Beta -TypeName P0009RoundTrip

            $csRender = ($csObject | Format-Table | Out-String).Trim()
            $psRender = ($psObject | Format-Table | Out-String).Trim()
        }

        It "inserts the same dbatools-prefixed type name as Select-DefaultView" {
            $csObject.PSObject.TypeNames[0] | Should -Be "dbatools.P0009RoundTrip"
            $csObject.PSObject.TypeNames[0] | Should -Be $psObject.PSObject.TypeNames[0]
        }

        It "renders only the curated default columns through the formatting engine" {
            $csRender | Should -Match "Alpha"
            $csRender | Should -Match "Beta"
            $csRender | Should -Not -Match "Gamma"
            $csRender | Should -Not -Match "Delta"
        }

        It "renders identically to the Select-DefaultView-decorated object" {
            $csRender | Should -Be $psRender
        }

        It "keeps the full property set reachable despite the curated display set" {
            $csObject.Gamma | Should -Be 3
            $csObject.Delta | Should -Be 4
        }
    }
}
