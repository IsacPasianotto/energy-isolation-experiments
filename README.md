# Energy decomposition: analysis of energy component


## Setup 

```bash
git clone ...
cd ...
git submodule update --init --recursive
```

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```



Step script:

- setup monitoring
- DB -> ~setup_ready~
- Wait 3 min for stabilization
- start with the fan:
  - DB -> ~starting_fan xxxx rpm~
  - wait
  - DB -> ~ending_fan xxxx rpm~
  - Repeat with different value.

- memstress

- netstress

- ...
