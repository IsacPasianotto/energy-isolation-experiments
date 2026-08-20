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



| Node     | N_channels | f_clock (MHz) | w_bus (bytes) | Available (GB) | B_peak (GB/s) | 80% B_peak(GB/s) |
| -------- | ---------- | ------------- | ------------- | -------------- | ------------- | ---------------- |
| thin008  | 12         | 2666          | 8             | 720            | 256           | 204.8            |
| fat002   | 24         | 2666          | 8             | 1500           | 512           | 409.6            |
| epyc007  | 16         | 3200          | 8             | 490            | 410           | 328              |
| genoa007 | 16         | 4800          | 8             | 500            | 614           | 491.2            |
| gpu002   | 8          | 2933          | 8             | 256            | 188           | 150.4            |


