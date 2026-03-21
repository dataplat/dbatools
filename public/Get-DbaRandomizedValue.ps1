function Get-DbaRandomizedValue {
    <#
    .SYNOPSIS
        Generates random data values for SQL Server data types or specialized data patterns for data masking and test data creation

    .DESCRIPTION
        Creates realistic fake data by generating random values that match SQL Server data type constraints or using specialized data patterns like names, addresses, and phone numbers.
        This function is essential for data masking in non-production environments, replacing sensitive production data with believable fake data while maintaining referential integrity and data patterns.
        Supports all major SQL Server data types (varchar, int, datetime, etc.) with proper ranges and formatting, plus hundreds of specialized randomizer types including personal information, financial data, and lorem ipsum text.
        Uses the Bogus library to ensure generated data follows realistic patterns rather than simple random character generation.

    .PARAMETER DataType
        Specifies the SQL Server data type for which to generate a random value that matches the type's constraints and range.
        Use this when you need to generate test data that exactly matches your column's data type, including proper ranges for numeric types and correct formatting for date/time types.
        Supported types include bigint, bit, bool, char, date, datetime, datetime2, decimal, int, float, guid, money, numeric, nchar, ntext, nvarchar, real, smalldatetime, smallint, text, time, tinyint, uniqueidentifier, userdefineddatatype, varchar.

    .PARAMETER RandomizerType
        Selects the category of realistic fake data to generate using the Bogus library instead of basic SQL data types.
        Use this when you need data that looks realistic for specific domains like names, addresses, or financial information rather than just type-appropriate random values.
        Available types include Address, Commerce, Company, Database, Date, Finance, Hacker, Hashids, Image, Internet, Lorem, Name, Person, Phone, Random, Rant, System.

    .PARAMETER RandomizerSubType
        Defines the specific type of data to generate within a RandomizerType category, such as 'FirstName' under Name or 'ZipCode' under Address.
        Use this to get precisely the kind of fake data you need, like generating just phone numbers from the Person category or specific address components.
        Can be used alone and the function will automatically determine the appropriate RandomizerType, or combined with RandomizerType for explicit control.

    .PARAMETER Min
        Sets the minimum value or length constraint for generated data, such as the shortest string length or smallest numeric value.
        Use this to ensure generated data meets your minimum requirements, like ensuring usernames are at least 3 characters or account balances are above zero.
        Defaults to 1 for most data types; automatically adjusted to data type limits for numeric types like int or smallint.

    .PARAMETER Max
        Sets the maximum value or length constraint for generated data, such as the longest string length or largest numeric value.
        Use this to prevent data from exceeding column limits or business rules, like keeping varchar fields under their defined length or amounts under spending limits.
        Defaults to 255 for most data types; automatically adjusted to data type limits for numeric types like int or smallint.

    .PARAMETER Precision
        Controls the number of decimal places for generated numeric values when using decimal, numeric, real, or float data types.
        Use this to match your column's precision requirements, ensuring generated monetary amounts or measurements have the correct decimal precision.
        Defaults to 2 decimal places, which works well for most currency and percentage values.

    .PARAMETER CharacterString
        Defines the character set to use when generating random string data for varchar, char, and similar text data types.
        Use this to match specific requirements like alphanumeric-only strings for account codes or excluding certain characters that cause issues in your application.
        Defaults to all letters (upper and lower case) and numbers; customize for specific business rules or technical constraints.

    .PARAMETER Format
        Applies custom formatting patterns to generated data, such as phone number formats like "(###) ###-####" or ZIP code patterns like "##### ####".
        Use this to ensure generated data matches your application's expected format, making masked data look consistent with production patterns.
        Works with randomizer types that support formatting; use # as placeholders that will be replaced with appropriate random digits or characters.

    .PARAMETER Symbol
        Adds a prefix symbol to generated numeric values, such as "$" for currency amounts or "%" for percentages.
        Use this when you need formatted output that matches how values are displayed in reports or applications, like generating "$1,234.56" instead of just "1234.56".
        Primarily used with Finance randomizer types for realistic monetary displays.

    .PARAMETER Separator
        Specifies the delimiter character to use in formatted data like MAC addresses, where you can choose between ":" or "-" separators.
        Use this to match your network infrastructure's standard format, ensuring generated MAC addresses use the same separator style as your production environment.
        Most commonly used with Internet randomizer types that generate network-related identifiers.

    .PARAMETER Value
        Provides the source data for transformation-based randomization methods, particularly when using the "Shuffle" subtype to rearrange existing values.
        Use this when you want to mask data by scrambling rather than replacing it entirely, preserving some characteristics like character count while making it unrecognizable.
        Required when using RandomizerSubType "Shuffle"; the function will randomize the order of characters while preserving commas and decimal points in their original positions.

    .PARAMETER Locale
        Controls the cultural context for generated data, affecting formats for names, addresses, phone numbers, and other locale-specific information.
        Use this when you need test data that matches your target region's conventions, such as generating European address formats or non-English names for international applications.
        Defaults to 'en' for English; change to other locale codes like 'de', 'fr', or 'es' to generate region-appropriate fake data.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, DataGeneration
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Scalar values with type determined by parameters (when using -DataType)

        System.Int64, System.Int32 (bigint, int, smallint, tinyint data types)
        - Returns a single integer value within the appropriate range for the specified data type

        System.Decimal, System.Single, System.Double (decimal, float, money, numeric, real data types)
        - Returns a single numeric value with optional symbol ($, %, etc.) and specified precision

        System.String (varchar, char, nvarchar, nchar, text, ntext data types)
        - Returns a string value with random characters from the specified CharacterString
        - Length controlled by Min and Max parameters (default 1-255 characters)

        System.String in date/time formats (date, datetime, datetime2, smalldatetime, time data types)
        - date: "yyyy-MM-dd" format
        - datetime: "yyyy-MM-dd HH:mm:ss.fff" format
        - datetime2: "yyyy-MM-dd HH:mm:ss.fffffff" format
        - smalldatetime: "yyyy-MM-dd HH:mm:ss" format
        - time: "HH:mm:ss.fffffff" format
        - uniqueidentifier/guid: GUID in standard format

        System.Int32 (bit, bool, userdefineddatatype)
        - Returns 0 or 1 for bit/bool types
        - Returns 0, 1, or $null for userdefineddatatype depending on Max parameter

        Specialized Randomizer Types (when using -RandomizerType/-RandomizerSubType)

        Variable return types from the Bogus library:
        - Address types (Address, ZipCode, City, State, Country, BuildingNumber, StreetName, Latitude, Longitude): System.String or System.Double
        - Commerce types (Product, Department, ProductName, Price): System.String or numeric
        - Company types (CompanyName, CatchPhrase, Bs): System.String
        - Database types (Engine, Column, CollationName, Type): System.String
        - Date types (formatted dates or timestamps based on subtype specification): System.String
        - Finance types (Account, Amount, CreditCardNumber, Iban, Bic): System.String or numeric
        - Hacker types (Phrase, Abbreviation, Adjective, Noun, Verb): System.String
        - Image types (URLs or image data): System.String
        - Internet types (Email, UserName, Password, Url, IpAddress, Mac, DomainName): System.String
        - Lorem types (Word, Words, Sentence, Sentences, Paragraph, Paragraphs, Slug, Letter, Lines): System.String or array
        - Name types (FirstName, LastName, FullName, Prefix, Suffix): System.String
        - Person types (various personal information): System.String or other types
        - Phone types (PhoneNumber with optional formatting): System.String
        - Random types (Int, Long, Double, Float, Decimal, Guid, String, Bytes): System.Int32, System.Int64, System.Double, System.Single, System.Decimal, System.String, or byte array
        - Rant types (Review, Reviews): System.String
        - System types (FileName, DirectoryPath, CommonFileName, CommonFileExt, CommonUserAgent): System.String

        All returned values are generated using the Bogus library which ensures realistic, contextually appropriate fake data rather than purely random values. The specific data type and format depends on the selected RandomizerType and RandomizerSubType combination, as well as format and pattern parameters applied.

    .LINK
        https://dbatools.io/Get-DbaRandomizedValue

    .EXAMPLE
        Get-DbaRandomizedValue -DataType bit

        Will return either a 1 or 0

    .EXAMPLE
        Get-DbaRandomizedValue -DataType int

        Will generate a number between -2147483648 and 2147483647

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerType Address -RandomizerSubType Zipcode

        Generates a random zipcode

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerType Address -RandomizerSubType Zipcode -Format "#### ##"

        Generates a random zipcode like "1234 56"

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType PhoneNumber -Format "(###) #######"

        Generates a random phonenumber like "(123) 4567890"

    #>
    [CmdLetBinding()]
    param(
        [string]$DataType,
        [string]$RandomizerType,
        [string]$RandomizerSubType,
        [object]$Min,
        [object]$Max,
        [int]$Precision = 2,
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string]$Format,
        [string]$Symbol,
        [string]$Separator,
        [string]$Value,
        [string]$Locale = 'en',
        [switch]$EnableException
    )


    begin {
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
            Stop-Function -Message "Please use one of the variables i.e. -DataType, -RandomizerType or -RandomizerSubType" -Continue
        } elseif ($DataType -and ($RandomizerType -or $RandomizerSubType)) {
            Stop-Function -Message "You cannot use -DataType with -RandomizerType or -RandomizerSubType" -Continue
        } elseif (-not $RandomizerSubType -and $RandomizerType) {
            Stop-Function -Message "Please enter a sub type" -Continue
        } elseif (-not $RandomizerType -and $RandomizerSubType) {
            $RandomizerType = $script:uniquesubtypes
        }

        if ($DataType -and $DataType.ToLowerInvariant() -notin $supportedDataTypes) {
            Stop-Function -Message "Unsupported sql data type" -Continue -Target $DataType
        }

        # Check the bogus type
        if ($RandomizerType) {
            if ($RandomizerType -notin $script:uniquerandomizertypes) {
                Stop-Function -Message "Invalid randomizer type" -Continue -Target $RandomizerType
            }
        }

        # Check the sub type
        if ($RandomizerSubType) {
            if ($RandomizerSubType -notin $script:uniquerandomizersubtype) {
                Stop-Function -Message "Invalid randomizer sub type" -Continue -Target $RandomizerSubType
            }

            if ($RandomizerSubType.ToLowerInvariant() -eq 'shuffle' -and $null -eq $Value) {
                Stop-Function -Message "Value cannot be empty when using sub type 'Shuffle'" -Continue -Target $RandomizerSubType
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
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($DataType -and -not $RandomizerSubType) {

            switch ($DataType.ToLowerInvariant()) {
                'bigint' {
                    if (-not $Min -or $Min -lt -9223372036854775808) {
                        $Min = -9223372036854775808
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 9223372036854775807) {
                        $Max = 9223372036854775807
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
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
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 2147483647 -or $Max -lt $Min) {
                        $Max = 2147483647
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
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
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 32767 -or $Max -lt $Min) {
                        $Max = 32767
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
                    }

                    $script:faker.Random.Int($Min, $Max)
                }
                'time' {
                    ($script:faker.Date.Past()).ToString("HH:mm:ss.fffffff")
                }
                'tinyint' {
                    if (-not $Min -or $Min -lt 0) {
                        $Min = 0
                        Write-Message -Level Verbose -Message "Min value for data type is empty or too small. Reset to $Min"
                    }

                    if (-not $Max -or $Max -gt 255 -or $Max -lt $Min) {
                        $Max = 255
                        Write-Message -Level Verbose -Message "Max value for data type is empty or too big. Reset to $Max"
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
                            Stop-Function -Message "Please set the minimum value for the date" -Continue -Target $Min
                        }

                        if (-not $Max) {
                            Stop-Function -Message "Please set the maximum value for the date" -Continue -Target $Max
                        }

                        if ($Min -gt $Max) {
                            Stop-Function -Message "The minimum value for the date cannot be later than maximum value" -Continue -Target $Min
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
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraph($Min)

                    } elseif ($randSubType -eq 'paragraphs') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Paragraphs($Min)

                    } elseif ($randSubType -eq 'letter') {
                        $script:faker.Lorem.Letter($Max)
                    } elseif ($randSubType -eq 'lines') {
                        $script:faker.Lorem.Lines($Max)
                    } elseif ($randSubType -eq 'sentence') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $script:faker.Lorem.Sentence($Min, $Max)

                    } elseif ($randSubType -eq 'sentences') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
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
}