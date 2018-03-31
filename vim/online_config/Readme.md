对于solarized主题， 配置好之后呢，在gvim下是可以完美显示的，但是终端下使用vim的时候，颜色还是很糟糕的。与预期不符。
那是因为终端默认不支持256色。 修改.bashrc 文件
```
vim .barshrc 并添加 
export TERM=xterm-256color
```
