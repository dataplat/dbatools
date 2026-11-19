#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates a single randomized value from a SQL data type or Bogus randomizer type/subtype. Port of
/// public/Get-DbaRandomizedValue.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port; there is NO ValueFromPipeline parameter, so process fires once (this command is called
/// once per value, e.g. by Get-DbaRandomizedDataset). The source begin block caches module script-scope state
/// ($script:faker, $script:randomizerTypes, $script:unique*) which persists in the real module scope, validates
/// the inputs (seven Stop-Function -Continue guards), and MUTATES the local $RandomizerType/$Min/$Max that process
/// consumes. Because process fires once, the begin block is PREPENDED (verbatim) into the process hop so those local
/// mutations are in scope for process. The whole body (begin+process) is wrapped in
/// foreach ($__continueGuard in @(1)) { ... } because the many Stop-Function -Continue guards (begin 212/214/216/222/228/235/239
/// and process 428/432/436) sit at non-loop locations, so their internal continue would otherwise escape the module
/// scriptblock (the bare-continue-in-hop hazard); continue still targets the nearest enclosing loop, so genuinely
/// loop-bound continues are unaffected. The verbatim if (Test-FunctionInterrupt) { return } is inert (all
/// Stop-Function are -Continue, which do not set the interrupt). Precision (int, default 2), CharacterString (string,
/// default), and Locale (string, default 'en') are reproduced via compiled property initializers. Edits: -FunctionName
/// Get-DbaRandomizedValue on the ten Stop-Function and twelve Write-Message. No value-passed switch, no Test-Bound, no
/// ShouldProcess. Surface pinned by migration/baselines/Get-DbaRandomizedValue.json (positions 0-11, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaRandomizedValue")]
public sealed class GetDbaRandomizedValueCommand : DbaBaseCmdlet
{
    /// <summary>The SQL data type to generate a value for.</summary>
    [Parameter(Position = 0)]
    public string? DataType { get; set; }

    /// <summary>The Bogus randomizer type.</summary>
    [Parameter(Position = 1)]
    public string? RandomizerType { get; set; }

    /// <summary>The Bogus randomizer subtype.</summary>
    [Parameter(Position = 2)]
    public string? RandomizerSubType { get; set; }

    /// <summary>The minimum value.</summary>
    [Parameter(Position = 3)]
    public object? Min { get; set; }

    /// <summary>The maximum value.</summary>
    [Parameter(Position = 4)]
    public object? Max { get; set; }

    /// <summary>The number of decimal places (default 2).</summary>
    [Parameter(Position = 5)]
    [PsIntCast]
    public int Precision { get; set; } = 2;

    /// <summary>The character set to draw string values from.</summary>
    [Parameter(Position = 6)]
    public string CharacterString { get; set; } = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    /// <summary>The output format string.</summary>
    [Parameter(Position = 7)]
    public string? Format { get; set; }

    /// <summary>The currency/number symbol.</summary>
    [Parameter(Position = 8)]
    public string? Symbol { get; set; }

    /// <summary>The separator string.</summary>
    [Parameter(Position = 9)]
    public string? Separator { get; set; }

    /// <summary>The value to shuffle (for the 'Shuffle' subtype).</summary>
    [Parameter(Position = 10)]
    public string? Value { get; set; }

    /// <summary>The locale used for value generation (default 'en').</summary>
    [Parameter(Position = 11)]
    public string Locale { get; set; } = "en";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            DataType, RandomizerType, RandomizerSubType, Min, Max, Precision, CharacterString, Format, Symbol,
            Separator, Value, Locale, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the source begin block (module-scope caching + input validation + local RandomizerType/Min/Max mutation,
    // VERBATIM + -FunctionName on its Stop-Function) PREPENDED to the process block (VERBATIM + -FunctionName on its
    // Stop-Function/Write-Message). The whole body is wrapped in a continue-guard foreach because many Stop-Function
    // -Continue guards sit at non-loop locations. Script-scope ($script:*) resolves in the real module scope.
    private const string ProcessScript = """
param($DataType, $RandomizerType, $RandomizerSubType, $Min, $Max, $Precision, $CharacterString, $Format, $Symbol, $Separator, $Value, $Locale, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$DataType, [string]$RandomizerType, [string]$RandomizerSubType, [object]$Min, [object]$Max, [int]$Precision, [string]$CharacterString, [string]$Format, [string]$Symbol, [string]$Separator, [string]$Value, [string]$Locale, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    foreach ($__continueGuard in @(1)) {
        # Create faker object
        if (-not $script:faker) {
            $script:faker = New-Object Bogus.Faker($Locale)
        }

        # Get all the random possibilities
        if (-not $script:randomizerTypes) {
            $script:randomizerTypes = Import-Csv (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\en.randomizertypes.csv") | Group-Object { $_.Type }
        }

        if (-not $script:uniquesubtypes) {
            $script:uniquesubtypes = $script:randomizerTypes.Group | Where-Object Subtype -eq $RandomizerSubType | Select-Object Type -ExpandProperty Type -First 1
        }

        if (-not $script:uniquerandomizertypes) {
            $script:uniquerandomizertypes = ($script:randomizerTypes.Group.Type | Select-Object -Unique)
        }

        if (-not $script:uniquerandomizersubtype) {
            $script:uniquerandomizersubtype = ($script:randomizerTypes.Group.SubType | Select-Object -Unique)
        }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check the variables
        if (-not $DataType -and -not $RandomizerType -and -not $RandomizerSubType) {
            Stop-Function -Message "Please use one of the variables i.e. -DataType, -RandomizerType or -RandomizerSubType" -Continue -FunctionName Get-DbaRandomizedValue
        } elseif ($DataType -and ($RandomizerType -or $RandomizerSubType)) {
            Stop-Function -Message "You cannot use -DataType with -RandomizerType or -RandomizerSubType" -Continue -FunctionName Get-DbaRandomizedValue
        } elseif (-not $RandomizerSubType -and $RandomizerType) {
            Stop-Function -Message "Please enter a sub type" -Continue -FunctionName Get-DbaRandomizedValue
        } elseif (-not $RandomizerType -and $RandomizerSubType) {
            $RandomizerType = $script:uniquesubtypes
        }

        if ($DataType -and $DataType.ToLowerInvariant() -notin $supportedDataTypes) {
            Stop-Function -Message "Unsupported sql data type" -Continue -Target $DataType -FunctionName Get-DbaRandomizedValue
        }

        # Check the bogus type
        if ($RandomizerType) {
            if ($RandomizerType -notin $script:uniquerandomizertypes) {
                Stop-Function -Message "Invalid randomizer type" -Continue -Target $RandomizerType -FunctionName Get-DbaRandomizedValue
            }
        }

        # Check the sub type
        if ($RandomizerSubType) {
            if ($RandomizerSubType -notin $script:uniquerandomizersubtype) {
                Stop-Function -Message "Invalid randomizer sub type" -Continue -Target $RandomizerSubType -FunctionName Get-DbaRandomizedValue
            }

            if ($RandomizerSubType.ToLowerInvariant() -eq 'shuffle' -and $null -eq $Value) {
                Stop-Function -Message "Value cannot be empty when using sub type 'Shuffle'" -Continue -Target $RandomizerSubType -FunctionName Get-DbaRandomizedValue
            }
        }

        if ($null -eq $Min) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Min = 1
            }
        }

        if ($null -eq $Max) {
            if ($DataType.ToLower() -notlike "date*" -and $RandomizerType.ToLower() -notlike "date*") {
                $Max = 255
            }
        }


        if (Test-FunctionInterrupt) { return }

        if ($DataType -and -not $RandomizerSubType) {

            switch ($DataType.ToLowerInvariant()) {
                'bigint' {
                    if (-not $Min -or $Min -lt -9223372036854775808) {
                        $Min = -9223372036854775808
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    if (-not $Max -or $Max -gt 9223372036854775807) {
                        $Max = 9223372036854775807
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    $script:faker.Random.Long($Min, $Max)
                }

                { $PSItem -in 'bit', 'bool' } {
                    if ($script:faker.Random.Bool()) {
                        1
                    } else {
                        0
                    }
                }
                'date' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'datetime2' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                { $PSItem -in 'decimal', 'float', 'money', 'numeric', 'real' } {
                    $script:faker.Finance.Amount($Min, $Max, $Precision)
                }
                'int' {
                    if (-not $Min -or $Min -lt -2147483648) {
                        $Min = -2147483648
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    if (-not $Max -or $Max -gt 2147483647 -or $Max -lt $Min) {
                        $Max = 2147483647
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    $script:faker.Random.Int($Min, $Max)

                }
                'smalldatetime' {
                    if ($Min -or $Max) {
                        ($script:faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        ($script:faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                    }
                }
                'smallint' {
                    if (-not $Min -or $Min -lt -32768) {
                        $Min = 32768
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    if (-not $Max -or $Max -gt 32767 -or $Max -lt $Min) {
                        $Max = 32767
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                'time' {
                    ($script:faker.Date.Past()).ToString("HH:mm:ss.fffffff")
                }
                'tinyint' {
                    if (-not $Min -or $Min -lt 0) {
                        $Min = 0
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    if (-not $Max -or $Max -gt 255 -or $Max -lt $Min) {
                        $Max = 255
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                { $PSItem -in 'uniqueidentifier', 'guid' } {
                    $script:faker.System.Random.Guid().Guid
                }
                'userdefineddatatype' {
                    if ($Max -eq 1) {
                        if ($script:faker.System.Random.Bool()) {
                            1
                        } else {
                            0
                        }
                    } else {
                        $null
                    }
                }
                { $PSItem -in 'char', 'nchar', 'nvarchar', 'varchar' } {
                    $script:faker.Random.String2($Min, $Max, $CharacterString)
                }

            }

        } else {

            $randSubType = $RandomizerSubType.ToLowerInvariant()

            switch ($RandomizerType.ToLowerInvariant()) {
                'address' {

                    if ($randSubType -in 'latitude', 'longitude') {
                        $script:faker.Address.Latitude($Min, $Max)
                    } elseif ($randSubType -eq 'zipcode') {
                        if ($Format) {
                            $script:faker.Address.ZipCode("$($Format)")
                        } else {
                            $script:faker.Address.ZipCode()
                        }
                    } else {
                        $script:faker.Address.$RandomizerSubType()
                    }

                }
                'commerce' {
                    if ($randSubType -eq 'categories') {
                        $script:faker.Commerce.Categories($Max)
                    } elseif ($randSubType -eq 'departments') {
                        $script:faker.Commerce.Department($Max)
                    } elseif ($randSubType -eq 'price') {
                        $script:faker.Commerce.Price($min, $Max, $Precision, $Symbol)
                    } else {
                        $script:faker.Commerce.$RandomizerSubType()
                    }

                }
                'company' {
                    $script:faker.Company.$RandomizerSubType()
                }
                'database' {
                    $script:faker.Database.$RandomizerSubType()
                }
                'date' {
                    if ($DataType -eq 'date') {
                        $formatString = "yyyy-MM-dd"
                    } elseif ($DataType -eq 'datetime') {
                        $formatString = "yyyy-MM-dd HH:mm:ss.fff"
                    } elseif ($DataType -eq 'datetime2') {
                        $formatString = "yyyy-MM-dd HH:mm:ss.fffffff"
                    }

                    if ($randSubType -eq 'between') {

                        if (-not $Min) {
                            Stop-Function -Message "Please set the minimum value for the date" -Continue -Target $Min -FunctionName Get-DbaRandomizedValue
                        }

                        if (-not $Max) {
                            Stop-Function -Message "Please set the maximum value for the date" -Continue -Target $Max -FunctionName Get-DbaRandomizedValue
                        }

                        if ($Min -gt $Max) {
                            Stop-Function -Message "The minimum value for the date cannot be later than maximum value" -Continue -Target $Min -FunctionName Get-DbaRandomizedValue
                        } else {
                            ($script:faker.Date.Between($Min, $Max)).ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'past') {
                        if ($Max) {
                            if ($Min) {
                                $yearsToGoBack = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoBack = 1
                            }

                            $script:faker.Date.Past($yearsToGoBack, $Max).ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Past().ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'future') {
                        if ($Min) {
                            if ($Max) {
                                $yearsToGoForward = [math]::round((([datetime]$Max - [datetime]$Min).Days / 365), 0)
                            } else {
                                $yearsToGoForward = 1
                            }

                            $script:faker.Date.Future($yearsToGoForward, $Min).ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            $script:faker.Date.Future().ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } elseif ($randSubType -eq 'recent') {
                        $script:faker.Date.Recent().ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                    } elseif ($randSubType -eq 'random') {
                        if ($Min -or $Max) {
                            if (-not $Min) {
                                $Min = Get-Date
                            }

                            if (-not $Max) {
                                $Max = (Get-Date).AddYears(1)
                            }

                            ($script:faker.Date.Between($Min, $Max)).ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                        } else {
                            ($script:faker.Date.Past()).ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    } else {
                        $script:faker.Date.$RandomizerSubType()
                    }
                }
                'finance' {
                    if ($randSubType -eq 'account') {
                        $script:faker.Finance.Account($Max)
                    } elseif ($randSubType -eq 'amount') {
                        $script:faker.Finance.Amount($Min, $Max, $Precision)
                    } else {
                        $script:faker.Finance.$RandomizerSubType()
                    }
                }
                'hacker' {
                    $script:faker.Hacker.$RandomizerSubType()
                }
                'image' {
                    $script:faker.Image.$RandomizerSubType()
                }
                'internet' {
                    if ($randSubType -eq 'password') {
                        $script:faker.Internet.Password($Max)
                    } elseif ($randSubType -eq 'mac') {
                        if ($Separator) {
                            $script:faker.Internet.Mac($Separator)
                        } else {
                            if (-not $Format -or $Format -eq "##:##:##:##:##:##") {
                                $script:faker.Internet.Mac()
                            } elseif ($Format -eq "############") {
                                $script:faker.Internet.Mac("")
                            } else {
                                $newMacArray = $Format.ToCharArray()

                                $macAddress = $script:faker.Internet.Mac("")
                                $macArray = $macAddress.ToCharArray()

                                $macIndex = 0
                                for ($i = 0; $i -lt $formatArray.Count; $i++) {
                                    if ($newMacArray[$i] -eq "#") {
                                        $newMacArray[$i] = $macArray[$macIndex]
                                        $macIndex++
                                    }
                                }

                                $newMacArray -join ""
                            }
                        }
                    } else {
                        $script:faker.Internet.$RandomizerSubType()
                    }
                }
                'lorem' {
                    if ($randSubType -eq 'paragraph') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                        }

                        $script:faker.Lorem.Paragraph($Min)

                    } elseif ($randSubType -eq 'paragraphs') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                        }

                        $script:faker.Lorem.Paragraphs($Min)

                    } elseif ($randSubType -eq 'letter') {
                        $script:faker.Lorem.Letter($Max)
                    } elseif ($randSubType -eq 'lines') {
                        $script:faker.Lorem.Lines($Max)
                    } elseif ($randSubType -eq 'sentence') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                        }

                        $script:faker.Lorem.Sentence($Min, $Max)

                    } elseif ($randSubType -eq 'sentences') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min" -FunctionName Get-DbaRandomizedValue -ModuleName "dbatools"
                        }

                        $script:faker.Lorem.Sentences($Min, $Max)

                    } elseif ($randSubType -eq 'slug') {
                        $script:faker.Lorem.Slug($Max)
                    } elseif ($randSubType -eq 'words') {
                        $script:faker.Lorem.Words($Max)
                    } else {
                        $script:faker.Lorem.$RandomizerSubType()
                    }
                }
                'name' {
                    $script:faker.Name.$RandomizerSubType()
                }
                'person' {
                    if ($randSubType -eq "phone") {
                        if ($Format) {
                            $script:faker.Phone.PhoneNumber($Format)
                        } else {
                            $script:faker.Phone.PhoneNumber()
                        }
                    } else {
                        $script:faker.Person.$RandomizerSubType
                    }
                }
                'phone' {
                    if ($Format) {
                        $script:faker.Phone.PhoneNumber($Format)
                    } else {
                        $script:faker.Phone.PhoneNumber()
                    }
                }
                'random' {
                    if ($randSubType -in 'byte', 'char', 'decimal', 'double', 'even', 'float', 'int', 'long', 'number', 'odd', 'sbyte', 'short', 'uint', 'ulong', 'ushort') {
                        $script:faker.Random.$RandomizerSubType($Min, $Max)
                    } elseif ($randSubType -eq 'bytes') {
                        $script:faker.Random.Bytes($Max)
                    } elseif ($randSubType -in 'string', 'string2') {
                        $script:faker.Random.String2([int]$Min, [int]$Max, $CharacterString)
                    } elseif ($randSubType -eq 'shuffle') {
                        $commaIndex = $value.IndexOf(",")
                        $dotIndex = $value.IndexOf(".")

                        $Value = (($Value -replace ',', '') -replace '\.', '')

                        $newValue = ($script:faker.Random.Shuffle($Value) -join '')

                        if ($commaIndex -ne -1) {
                            $newValue = $newValue.Insert($commaIndex, ',')
                        }

                        if ($dotIndex -ne -1) {
                            $newValue = $newValue.Insert($dotIndex, '.')
                        }

                        $newValue
                    } else {
                        $script:faker.Random.$RandomizerSubType()
                    }
                }
                'rant' {
                    if ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Review($script:faker.Commerce.Product())
                    } elseif ($randSubType -eq 'reviews') {
                        $script:faker.Rant.Reviews($script:faker.Commerce.Product(), $Max)
                    }
                }
                'system' {
                    $script:faker.System.$RandomizerSubType()
                }
            }
        }
    }
} $DataType $RandomizerType $RandomizerSubType $Min $Max $Precision $CharacterString $Format $Symbol $Separator $Value $Locale $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
