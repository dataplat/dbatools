# Parameter & Variable Naming Directive

## PARAMETER USAGE PATTERNS

Convert 1-2 parameter calls to direct parameter format.

Convert 3+ parameter calls to splatting with `$splat<Purpose>` naming (never plain `$splat`).

Align all splat hashtable assignment operators with consistent spacing:

```powershell
# Direct parameters
$ag = Get-DbaLogin -SqlInstance $instance -Login $loginName

# Splat with purpose suffix - aligned = signs
$splatPrimary = @{
    Primary      = $TestConfig.instance3
    Name         = $primaryAgName
    ClusterType  = "None"
    FailoverMode = "Manual"
    Certificate  = "dbatoolsci_AGCert"
    Confirm      = $false
}
$primaryAg = New-DbaAvailabilityGroup @splatPrimary
```

## VARIABLE SCOPE MANAGEMENT

Replace all generic variable names with unique, descriptive names across all scopes to prevent collisions.

Rename variables in BeforeAll blocks to include scope-specific prefixes or suffixes:

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $primaryAgName = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary = $TestConfig.instance3
            Name    = $primaryAgName
            ...
        }
        $ag = New-DbaAvailabilityGroup @splatPrimary
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary = $TestConfig.instance3
                Name    = $replicaAgName
                ...
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }
    }
}
```