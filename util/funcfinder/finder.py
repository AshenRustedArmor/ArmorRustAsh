import requests

import re
import argparse

import sys
import time

# ===== Configuration =====
# Sourcing
REPOSITORIES = [
    {"owner": "AshenRustedArmor", "repo": "Titanfall2", "branch": "master", "tag": "V", "source_globals": True},
    {"owner": "AshenRustedArmor", "repo": "NorthstarMods", "branch": "main", "tag": "M", "source_globals": False}
]

class ItemsCrossReferencer:
    def __init__(self, token=None, output_file="registry_usage_report.txt"):
        self.headers = {"Accept": "application/vnd.github.v3+json"}
        if token:
            self.headers["Authorization"] = f"token {token}"
            
        self.output_file = output_file
        self.global_functions = []
        self.references = {} # { function_name: [ "[V] scripts/...", "[M] mods/..." ] }

    def run(self):
        """Main execution pipeline."""
        self.extract_globals()
        self.scan_repositories()
        self.generate_report()

    def extract_globals(self):
        """Finds the repo flagged with source_globals and extracts function definitions."""
        source_repo = next((r for r in REPOSITORIES if r.get("source_globals")), None)
        if not source_repo:
            print("CRITICAL: No repository flagged with 'source_globals: True'.")
            sys.exit(1)

        print(f"Fetching base functions from {source_repo['owner']}/{source_repo['repo']}...")
        
        # 1. Get the tree to find _items.nut
        api_url = f"https://api.github.com/repos/{source_repo['owner']}/{source_repo['repo']}/git/trees/{source_repo['branch']}?recursive=1"
        resp = requests.get(api_url, headers=self.headers)
        if resp.status_code != 200:
            print(f"Failed to fetch tree for {source_repo['repo']}. Status: {resp.status_code}")
            sys.exit(1)

        tree = resp.json().get("tree", [])
        items_nut_path = next((item["path"] for item in tree if "_items.nut" in item["path"]), None)
        
        if not items_nut_path:
            print("CRITICAL: Could not find '_items.nut' in the source repository.")
            sys.exit(1)

        # 2. Download and parse _items.nut
        raw_url = f"https://raw.githubusercontent.com/{source_repo['owner']}/{source_repo['repo']}/{source_repo['branch']}/{items_nut_path}"
        resp = requests.get(raw_url, headers=self.headers)
        
        matches = re.findall(r"global\s+function\s+([A-Za-z0-9_]+)", resp.text)
        self.global_functions = list(set(matches))
        
        for func in self.global_functions:
            self.references[func] = []
            
        print(f"Extracted {len(self.global_functions)} global functions to track.\n")

    def scan_repositories(self):
        """Loops through all defined repositories and scans their script files."""
        for repo in REPOSITORIES:
            print(f"Scanning repository: {repo['owner']}/{repo['repo']} [{repo['tag']}]")
            
            api_url = f"https://api.github.com/repos/{repo['owner']}/{repo['repo']}/git/trees/{repo['branch']}?recursive=1"
            raw_base = f"https://raw.githubusercontent.com/{repo['owner']}/{repo['repo']}/{repo['branch']}/"
            
            resp = requests.get(api_url, headers=self.headers)
            if resp.status_code != 200:
                print(f"  -> Failed to fetch tree. Skipping.")
                continue
                
            tree = resp.json().get("tree", [])
            script_files = [item["path"] for item in tree if item["path"].endswith((".nut", ".gnut"))]
            
            print(f"  -> Found {len(script_files)} scripts.")
            
            for i, file_path in enumerate(script_files):
                # Ignore the source file itself
                if repo.get("source_globals") and "_items.nut" in file_path:
                    continue
                    
                if i % 100 == 0 and i > 0:
                    print(f"     ...scanned {i}/{len(script_files)} files")
                    time.sleep(0.5) # Gentle rate limiting
                    
                resp = requests.get(f"{raw_base}{file_path}", headers=self.headers)
                if resp.status_code != 200:
                    continue
                    
                content = resp.text
                for func in self.global_functions:
                    if re.search(r'\b' + func + r'\b', content):
                        # Format: [V] path/to/file.nut
                        self.references[func].append(f"[{repo['tag']}] {file_path}")
            print("  -> Scan complete.\n")

    def generate_report(self):
        """Writes the findings to a text file."""
        print(f"Writing results to {self.output_file}...")
        with open(self.output_file, 'w', encoding='utf-8') as f:
            f.write(f"=== _items.nut External Usage Report ===\n\n")
            
            for func in sorted(self.references.keys()):
                usage_list = self.references[func]
                if len(usage_list) == 0:
                    f.write(f"[UNREFERENCED] {func}\n")
                else:
                    f.write(f"[USED] {func} ({len(usage_list)} references):\n")
                    for path in usage_list:
                        f.write(f"  -> {path}\n")
                f.write("\n")
        print("Done!")

def main():
    parser = argparse.ArgumentParser(description="Multi-Repo GitHub Scraper")
    parser.add_argument("-o", "--output", default="registry_usage_report.txt", help="Output file name")
    parser.add_argument("-t", "--token", default=None, help="GitHub PAT (Overrides token.secret)")
    
    args = parser.parse_args()
    
    active_token = args.token
    if not active_token:
        try:
            with open("token.secret", "r", encoding="utf-8") as f:
                active_token = f.read().strip()
                print("Loaded GitHub token from 'token.secret'.")
        except FileNotFoundError:
            pass
            
    if not active_token:
        print("WARNING: Running without a GitHub token. You may hit rate limits.")
    
    scraper = ItemsCrossReferencer(token=active_token, output_file=args.output)
    scraper.run()

if __name__ == "__main__":
    main()