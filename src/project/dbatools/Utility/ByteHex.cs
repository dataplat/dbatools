using System.Globalization;
using System.Text;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// private/functions/Convert-ByteToHexString.ps1 parity: renders a byte array as an
    /// uppercase "0x"-prefixed hex string ([byte[]]@(1,100,23,54) -> "0x01641736") for SMO
    /// login sids and hashed passwords. Faithful quirk: a NULL input yields "0x00" - the
    /// helper pipes $InputObject through ForEach-Object, and a bare $null pipes exactly
    /// once, formatting to "" and left-padding to "00" - while an EMPTY array pipes zero
    /// times and yields "0x". Callers span the security (New-DbaLogin, 3 sites) and backup
    /// (Test-DbaBackupEncrypted) families, hence the shared runtime placement (helper
    /// retained at refcount 4).
    /// </summary>
    public static class ByteHex
    {
        /// <summary>The helper's body: "0x" plus each byte as uppercase two-digit hex.</summary>
        public static string Convert(byte[] inputObject)
        {
            StringBuilder outString = new StringBuilder("0x");
            if (inputObject == null)
            {
                // PS: $null | ForEach-Object runs the block once; "{0:X}" -f $null is ""
                // and PadLeft(2, "0") makes it "00".
                outString.Append("00");
                return outString.ToString();
            }
            foreach (byte value in inputObject)
                outString.Append(value.ToString("X2"));
            return outString.ToString();
        }

        /// <summary>
        /// private/functions/Convert-HexStringToByte.ps1 parity (TB-015), the inverse
        /// helper: hex string to bytes for SMO login sids and hashed passwords. Sole live
        /// caller New-DbaLogin.ps1:255 (Sid). Faithful quirks, probed 5.1 + 7.6:
        /// TrimStart("0x") strips the CHARACTER SET {'0','x'} (case-sensitively - "0X1234"
        /// keeps its X and dies in Parse with FormatException), NOT the prefix - so leading
        /// ZERO BYTES are silently destroyed ("0x000501" -> {5,1}, "0x00641736" ->
        /// {100,23,54}; the doc example "0x01641736" survives only because the odd-length
        /// pad re-adds the stripped zero) and inputs whose every char is 0/x ("", "0x",
        /// "0", "0x0000") strip to empty, where the PS descending range 0..-1 makes
        /// Substring(0,2) throw ArgumentOutOfRangeException - an all-zero hex CRASHES the
        /// helper. [Int16]::Parse(s,'HexNumber') tolerates leading/trailing whitespace in
        /// a pair ("1 23" -> {1,35}) and lowercase hex. PS pipeline shape divergence
        /// (documented; probed): the PS caller receives Object[] for multi-byte results
        /// and a SCALAR byte for single-byte ones - this port always returns byte[]; SMO
        /// coerces all three identically. A null argument is the PS [string] binder's
        /// empty string (probed: $null -eq $s is False inside the function) and throws
        /// like it, per above.
        /// CALLER REACHABILITY MAP for STRING Sids (opus TB-015; New-DbaLogin.ps1:247-257
        /// pre-validates with the SAME char-set trim then rejects chars outside
        /// "0123456789ABCDEF" case-insensitively): REACHABLE - normal hex, lowercase hex,
        /// the leading-zero destruction, and the all-zero crash (the guard's trim empties
        /// "0x0000" so its foreach validates zero chars and passes it straight through);
        /// GUARD-REJECTED - uppercase X, non-hex, whitespace (Stop-Function
        /// InvalidArgument first). The crash throw escapes the caller's begin block with
        /// NO try/catch - it BYPASSES the Stop-Function/-EnableException contract the
        /// guard's own rejections honor (codex TB-015 r2 scope note: $Sid is [object], so
        /// a truthy non-string/non-Byte[] Sid already dies at the guard's own
        /// $Sid.TrimStart with the same uncaught-throw shape - the bypass is not unique
        /// to the all-zero crash); whether the compiled New-DbaLogin keeps the hard
        /// throws or folds them into its error contract is flagged to the W2 security row
        /// alongside the leading-zero-destruction flag.
        /// </summary>
        public static byte[] ToBytes(string inputObject)
        {
            string hexString = (inputObject ?? string.Empty).TrimStart('0', 'x');
            if (hexString.Length % 2 == 1)
                hexString = "0" + hexString;
            if (hexString.Length == 0)
            {
                // PS: 0..(0/2 - 1) is the DESCENDING range {0,-1}; index 0's
                // Substring(0, 2) on the empty string throws first. Reproduce it.
                hexString.Substring(0, 2);
            }
            byte[] outBytes = new byte[hexString.Length / 2];
            for (int i = 0; i < outBytes.Length; i++)
            {
                // PS: [Int16]::Parse($pair, 'HexNumber') - two hex digits always fit the
                // byte after the PS [byte[]] cast; HexNumber's whitespace tolerance rides
                // along on purpose.
                outBytes[i] = (byte)short.Parse(hexString.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.CurrentCulture);
            }
            return outBytes;
        }
    }
}
