# Messenger source moved

The Android messenger lives in a **separate public repository**:

**https://github.com/sk1tzwzd/WraithLink-Messenger**

Clone it as a sibling of this toolkit:

```bash
cd ..
git clone https://github.com/sk1tzwzd/WraithLink-Messenger.git
```

Or set `export WL_CHAT_SRC=/path/to/WraithLink-Messenger`.

Stage into a GrapheneOS/WraithLink product tree:

```bash
apps/chat/build-and-stage.sh "$WL_SRC_DIR"
```

Prebuilt APK: https://www.wraithlink.com/downloads/
