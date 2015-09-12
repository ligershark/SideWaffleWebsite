using Octokit;
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Xml;

namespace SideWaffleWebsite5.Models
{
    public class Client
    {
        /*  The personal access token for GitHub is 471fb3cc3c4ada426d1d4710b8c092907ae595d4
         *  This token allows us to access the repo's public information without having to
         *  do any type of authentication like OAuth.
        */
        private const string accessToken = "471fb3cc3c4ada426d1d4710b8c092907ae595d4";
        private GitHubClient client;

        public Client()
        {
            // Use basic authentication to make the requests
            client = new GitHubClient(new ProductHeaderValue("side-waffle"))
            {
                Credentials = new Credentials(accessToken)
            };
        }

        /// <summary>
        /// Using the most recent release on GitHub this function downloads the content of the specified file.
        /// </summary>
        private async Task<string> DownloadGitHubReleaseAsset(string fileName)
        {
            var request = client.Release.GetAll("ligershark", "side-waffle");

            var releases = await request;
            var latestRelease = releases[0];

            var assets = await client.Release.GetAllAssets("ligershark", "side-waffle", latestRelease.Id);
            string assetURL = "";

            foreach (var asset in assets)
            {
                if (asset.Name.Equals(fileName))
                {
                    assetURL = asset.BrowserDownloadUrl;
                }
            }

            var response = await client.Connection.GetHtml(new Uri(assetURL, UriKind.Absolute));
            
            return response.Body;
        }

        public string GetReleaseNotes()
        {
            var html = DownloadGitHubReleaseAsset("release-notes.xml").Result;

            return html;
        }

        public string GetFeaturesList()
        {
            var xml = DownloadGitHubReleaseAsset("template-report.xml").Result;

            return xml;
        }

        public List<string> GetUniqueNames(XmlNodeList nodes)
        {
            List<string> list = new List<string>();
            foreach (XmlNode node in nodes)
            {
                var attr = node.Attributes["Name"] ?? node.Attributes["Title"];
                string name = attr.InnerText;
                if (!list.Contains(name) && name.IndexOf("sample", StringComparison.OrdinalIgnoreCase) == -1)
                    list.Add(name);
            }

            list.Sort();
            list.Reverse();

            return list;
        }

        public List<string> GetVersionNotes(XmlNodeList nodes)
        {
            List<string> list = new List<string>();

            foreach (XmlNode node in nodes)
            {
                list.Add(node.InnerText);
            }

            list.Sort();

            return list;
        }
    }
}