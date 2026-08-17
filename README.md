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



## Personal annotation...

Fan can not be controlled by ipmitool, due to dell limitation


## Memstress


To compute the Theoretical BW:

$$
\mathcal{B}_{\text{peak}} =
N_{\text{channels}} \cdot
f_{\text{clock}} \cdot
w_{\text{bus}}
$$

Where:

- $N_{\text{channels}}$ is the number of memory channels in the system.
- $f_{\text{clock}}$ is the clock frequency of the memory.
- $w_{\text{bus}}$ is the width of the memory bus (in bytes).



| Node     | N_channels | f_clock (MHz) | w_bus (bytes) | Available (GB) | B_peak (GB/s) |
| -------- | ---------- | ------------- | ------------- | -------------- | ------------- |
| thin007  | 12         | 2666          | 8             | 720            | 256           |
| fat001   | 24         | 266           | 8             | 1500           | 512           |
| epyc001  | 16         | 3200          | 8             | 490            | 410           |
| genoa001 | 16         | 4800          | 8             | 500            | 614           |


