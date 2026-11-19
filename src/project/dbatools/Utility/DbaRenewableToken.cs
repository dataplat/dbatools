using System;
using System.Management.Automation;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// Thin wrapper around IRenewableToken, so we can start using it in Connect-DbaInstance
    /// </summary>
    public class DbaRenewableToken : IRenewableToken
    {
        private string _token;
        private string _resource;
        private string _tenant;
        private string _userId;
        private DateTimeOffset _expiry;

        #region Constructors
        /// <summary>
        /// Build from every property
        /// </summary>
        /// <param name="Token"></param>
        /// <param name="Resource"></param>
        /// <param name="Tenant"></param>
        /// <param name="UserId"></param>
        /// <param name="expiresOn"></param>
        public DbaRenewableToken(
            string Token,
            string Resource,
            string Tenant,
            string UserId,
            DateTimeOffset expiresOn
        )
        {
            _token = Token;
            _resource = Resource;
            _tenant = Tenant;
            _userId = UserId;
            _expiry = expiresOn;
        }

        /// <summary>
        /// Build from token and expiry
        /// </summary>
        /// <param name="Token"></param>
        /// <param name="expiresOn"></param>
        public DbaRenewableToken(string Token, DateTimeOffset expiresOn)
        {
            _token = Token;
            _expiry = expiresOn;
        }

        /// <summary>
        /// Build from SqlAuthenticationToken
        /// </summary>
        /// <param name="Token"></param>
        public DbaRenewableToken(SqlAuthenticationToken Token)
        {
            _token = Token.AccessToken;
            _expiry = Token.ExpiresOn;
        }

        /// <summary>
        /// Build from PSObject, as returned by Get-AzAccessToken
        /// </summary>
        /// <param name="Token"></param>
        public DbaRenewableToken(PSObject Token)
        {
            if (Token.Properties["AccessToken"] != null)
            {
                _token = Token.Properties["AccessToken"].Value.ToString();
            }
            _expiry = DateTimeOffset.Parse(Token.Properties["ExpiresOn"].Value.ToString());
            _resource = string.Empty;
            _tenant = Token.Properties["TenantId"].Value.ToString();
            _userId = Token.Properties["UserId"].Value.ToString();
        }
        #endregion

        DateTimeOffset IRenewableToken.TokenExpiry
        {
            get { return _expiry; }
        }

        string IRenewableToken.Resource
        {
            get { return _resource; }
        }

        string IRenewableToken.Tenant
        {
            get { return _tenant; }
        }

        string IRenewableToken.UserId
        {
            get { return _userId; }
        }

        string IRenewableToken.GetAccessToken()
        {
            return _token;
        }
    }
}
