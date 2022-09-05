# Stateless Arch (transactional)<h1>

**Esse é um projeto de atualizações contínuas. Se assegure de ter uma cópia recente do repositório antes de testar. As releases são unicamente para marcar a evolução do código, e não devem ser usadas**

Inspirado em sistemas como o Clear Linux, Fedora SilverBlue e Suse MicroOS, decidi tentar trazer algo semelhante a eles para o ArchLinux. Essa ferramenta visa permitir que o root controlado pelo pacman seja diferente do root do sysadmin. Dessa forma, é possível descartar configurações problemáticas sem perder atualizações. E usando uma abordagem transacional, também é possível fazer atualizações em uma "nova branch" do sistema, de forma que o root atualmente em uso não é tocado.


Se valendo de overlayfs, e de como é fácil adicionar tarefas ao init do ArchLinux, um script embutido no initrd se encarregará de montar /etc/, /var, /root, /mnt, /home, /opt, /srv, /usr/local e /usr/lib/systemd com permissão de leitura e escrita sobre uma raiz read-only (inspirado pelo código de Antynea em [Grub Btrfs](https://github.com/Antynea/grub-btrfs/blob/master/initramfs/Arch%20Linux/overlay_snap_ro-hook)).

É possível fazer isso sobre qualquer sistema de arquivos, porém, com btrfs, se ganha outra capacidade, como se sabe: snapshots baratos. Para os efeitos desse documento, sempre que ler branch, pense em snapshot btrfs.

**Dado que o pacman envia para stdout o status da operação, e que arch-chroot é capaz de rodar comandos, e trazer seu status de saída de volta para o host, via snapshots btrfs se faz possível que a operação sempre seja feita não diretamente no root atualmente em uso, e sim em uma nova "branch" do sistema. Assim, como um git, o status da operação de "merge" dos novos pacotes define se aquela branch se tornará o novo padrão do "repositório". Se o merge for bem sucedido, a branch é promovida. Caso contrário, ela é descartada. Nenhum bit do root atualmente em uso é tocado durante uma operação de "merge", portanto, por menores que sejam as adições/modificações, se faz necessário reiniciar para usá-las.**

[Se você estiver familiarizado com o funcionamento das atualizações do Opensuse Kubic/MicroOs](https://kubic.opensuse.org/documentation/transactional-update-guide/transactional-update.html), apenas lhe dizer que aqui todas as transações rodam com --continue por padrão, e voltam para current-root apenas em caso de erros críticos na manipulação de new-roots ainda não bootados bastará para ter uma ideia geral do sistema.

Para quem não tem familiaridade com um sistema de arquivos com suporte a snapshots + abordagem transacional, usar termos de git para se referir ao manuseio do sistema pode tornar a comunicação mais clara.

Em Stateless-Arch transacional, adicionar e remover programas, bem como quaisquer intervenções no root verdadeiro significa:

1. checkout -b transacional main
2. modificar a branch transactional (atualização, instalação e remoção de pacotes, "merge" a partir de outro remoto, os repositórios do ArchLinux no caso)

3. se o processo de merge for bem sucedido, faça 
* branch -m main old-main-date-operation
* branch -m transactional main
* o próximo boot implica em checkout main

3. se o processo de merge for mal sucedido, faça 
* git branch -D transactional

**Assim como num repositório, o processo de merge de novo código (no caso de um sistema, adição/remoção de programas) ser bem sucedido NÃO IMPLICA em um perfeito funcionamento posterior do código em si. Mas usando uma abordagem transacional, o sysadmin sempre terá um root de estado conhecido para o qual voltar (branch -m main broken-main && checkout -b main old-main-date-operation).**


# Implementação <h2>

implementar Stateless Arch em uma instalação nova é simples como:

* pacstrap em um único subvolume btrfs (/boot incluso). Deve constar nos pacotes, arch-install-scripts grub grub-btrfs bash e git;
* arch-chroot no subvolume;
* passwd;
* gerar locales;
* git clone desse repositório(pode ser em /tmp);
* executar o scritp install-stateless-arch-tools.sh
* seguir as instruções finais do scritp (somente operações normais em qualquer instalação do ArchLinux)
* reiniciar

(é possível implementar numa instalação existente, mas os passos necessários mudam conforme o ponto de partida; deixo para você a tarefa de descobrir quais passos são esses :wink:)

# Arquitetura <h3>

Ao concluir o boot, a raiz consistirá em duas camadas, sendo:

**Primeira camada: PacmanRoot**: um subvolume btrfs, com permissão somente leitura, onde está instalado o ArchLinux, com todas as pastas do root, **incluindo** /boot (obviamente /boot/efi será um ponto de montagem para fat32 EFI durante a instalação da grub, se efi). Esse root pode inicialmente possuir configurações mínimas, somente senha root, locales, e os arquivos e modificações necessárias para que Stateless Arch funcione. O próprio fstab não precisa ficar aqui, sua edição durante a instalação do sistema pode ser ignorada. Em todo boot de uma instalação com Stateless-Arch transacional, o PacmanRoot terá sua permissão de escrita trocada para false.


**Segunda camada: Sysadmin** um subvolume btrfs com permissão de leitura e escrita, que conterá diretórios para permitir montagem overlay com permissão de escrita em /etc/, /var, /root, /mnt, /home, /opt, /srv, /usr/local/ e /usr/lib/systemd, acima da camada somente leitura anterior. Assim, configurações de serviços, montagem, udev e afins podem ser honradas apropriadamente pelo systemd, na fase 2 da inicialização, e scripts customizados relacionados á suspensão e desligamento podem ser criados livremente (IMPORTANTE= alterar atributos dos binários sobre o overlay, após o sistema devidamente iniciado, ainda que não afete os arquivos reais, pode causar problemas na inicialização seguinte; esse overlay em específico (/usr/lib/systemd/) deve ser usado somente nos casos acima mencionados, adicionar scripts e serviços associados a suspensão e desligamento do sistema.). O subvolume que abriga os overlays tem o nome e o tipo de compressão explicitamente declarados no init; renomear o subvolume sem mudá-lo em /usr/lib/initcpio/hooks/stateless-mode-boot e reconstruir o init implica em um boot quebrado. Esse subvolume retem o estado do sistema, e pode ser simplesmente descartado (ou renomeado). **Desde que um novo seja criado**, no boot seguinte o scritp no initrd se encarregará de criar os diretórios necessários para essa camada. O sistema iniciará então no branch mais recente de PacmanRoot, mas sem as configurações do sysadmin. Um usuário com experiência mínima em btrfs pode fazer essa operação manualmente de forma trivial, mas isso não é necessário: base-manager --reset-sysadmin-data intermedia essa operação de forma simples.

**ATENÇÃO: conforme explicado no script de implementação, o hook que torna isso possível deve ser o último em HOOKS no /etc/mkinitcpio.conf, é compatível com os hooks ativos por padrão no ArchLinux, e NÃO é compatível com os hooks grub-btrfs-overlayfs e systemd; a combinação com outros hooks não foi testada**

# Sobre pontos de montagem e serviços <h4>

Ainda que não seja necessária a presença de PacmanRoot no fstab para o sucesso do boot, é uma boa prática que ele esteja lá. Pelo menos nos meus testes, quando ele não está presente, opções de montagem referentes a compressão de todos os subvolumes do mesmo dispositivo de bloco não são honradas. Então tenha sim / no fstab, apenas por esse motivo. Se não usar compressão, pode ignorar esse aviso.

**É uma boa prática existir uma montagem verdadeira para /home/$USER no fstab do sysadmin**, que será montada sobre o overlay de /home. Ferramentas de gerenciamento de container (docker/podman) não funcionam corretamente quando seu armazenamento é um overlay. Crie um subvolume/partição para a home de cada usuário da máquina, e os coloque corretamente no fstab. O mesmo pode ser verdade (não testado) para bancos de dados e imagens de máquinas virtuais nos diretórios aninhados em /var. Se usa algumas dessas coisas no dia a dia, e precisa que fiquem na hierarquia de /var, tenha partições e subvolumes verdadeiros para montar apropriadamente. Enfim, teste suas montagens antes de migrar totalmente para Stateless Arch, e verifique se quaisquer inconsistências encontradas podem ser resolvidas criando um ponto de montagem dedicado.

# Usabilidade <h6>

Para usar um ArchLinux com Stateless Arch, o sysadmin deve aceitar e conviver com algumas limitações e mudanças de usabilidade:

* atualização e remoção de pacotes somente de forma mediada por pac-base, não diretamento pelo pacman(discutido a seguir), e precisando reiniciar para ter acesso às modificações;

* como já deu para perceber, grub como bootloader é uma exigencia aqui. Faço isso para poder incluir o próprio kernel nos branchs. Dado que a grub consegue lidar com kernel e initrd sob btrfs, comprimido ou não, seja em legacy ou em efi, se torna uma ferramenta com um fator social e até mesmo ambiental importante : hardware sem capacidade de boot efi continua sendo suportado, e ao ter toda a raiz inclusa em branchs, a recuperação de uma atualização problemática, ou mesmo um reset total não passa por mais carga de acesso aos repositórios para baixar iso e pacotes. Mesmo implementar o ArchLinux em outra máquina se torna fácil como um btrfs send via ssh de seu último branch, com a certeza que isso não incluirá chaves ssh,configurações de sysadmins e grupos, pontos de acesso wifi, ou outras configurações sensíveis. PacmanRoot está sempre em "estado de pacstrap", ou muito perto disso. 


* a geração de locale-gen deve ser incluída diretamente na raiz, como já citado no processo de implementação, o que pode ser inconveniente caso o sysadmin troque constantemente de idioma; editar a raiz diretamente será discutido a seguir. Uma alternativa pode ser, durante a instalação do sistema, antes de implementar Stateless Arch, descomentar todos os locales em /etc/locale.gen, e gerar todos.

* Se valer primariamente de flatpak, appimage, ou, minha alternativa preferida, o excelente [Distrobox](https://github.com/89luca89/distrobox) de 89luca89. Dado que tanto /var quando a home do usuario são separados (ver considerações na sessão sobre montagens), voltar branchs da raiz não implica em perder acesso a nenhum desses programas. Delegue á base somente o suficiente para subir o modo gráfico, drivers em geral, suporte a hardware, virtualizadores, o suporte a containers,e outras ferrramentas que dependam de alto nivel de acesso, como por exemplo particionadores de disco.  Mesmo programas de edição de som são plenamente usáveis de dentro de um container (testado usando pipewire e wireplumber). O próprio DistroBox pode ser instalado na home de usuário. Os ícones de desktop de flatpaks, appimages e exportados via Distrobox surgem normalmente em sua área de trabalho, o funcionamento é totalmente transparente. E com distrobox é possível usar pacotes de outras distribuições, não somente do ArchLinux (eu tenho a leve impressão que a maior parte dos usuários de Stateless Arch usará Alpine como imagem padrão do Distrobox sempre que possível). [Na verdade, você até mesmo não instalar a sessão gráfica no root, e sim dentro de um container, de forma a ter uma sessão de usuário inteiramente segura, de onde não é possível usar comandos perigosos como dd, e ainda assim, instalar e remover pacotes normalmente.](https://github.com/89luca89/distrobox/blob/main/docs/posts/run_latest_gnome_kde_on_distrobox.md) Para uma sessão Gnome mínima no ArchLinux no Distrobox, basta os pacotes gnome-shell, gnome-session, e gnome-control-center.(PS.: o suporte a rede e a som deve ser instalado e iniciado pelo usuário real no root real, e a partir daí ele será passado para o "container de sessão" de forma transparente, permitindo parear dispositivos bluetooth, ou adicionar novas redes wifi, e usar o som normalmente. O uso de gdm no host como gestor de login é altamente recomendado).

# Manutenção <h7>

Os scripts base-manager e pac-base serão salvos em /usr/local/sbin, de forma que uma edição do sysadmin em seu próprio overlay valerá para alterar quaisquer parâmetros que queira. **Isso NÃO é verdadeiro para o hook do init.**

Base-manager acumula algumas funções, uma delas foi citada acima, as demais serão discutidas brevemente abaixo; veja em detalhes clonando esse repositório, e executando base-manager --help (uma das funções).

Atualizações e manuseio de programas são possíveis usando pac-base, seguido da cli normal do pacman (ex: pac-base -Syu). Pac-base criará uma nova branch do sistema (transacional) a partir da branch padrão, montará diretamente, e por cima dele uma montagem bind de /var/cache/pacman/pkg, /etc/mkinitcpio.conf,/etc/mkinitcpio.d./etc/modprobe.d, /etc/pacman.d, /etc/pacman.conf, /usr/local do sysadmin, e em seguida, provido por arch-install-scripts, executará "arch-chroot pacman" exportando os comandos passados para pac-base. O pacman no ambiente chroot executará a transação. Em caso de sucesso, pac-base receberá essa informação, e então irá tornar a branch padrão em uma branch secundária, e a branch transacional como padrão, usando para isso simples mudanças de nome das branchs, e atualização de bootloader (grub), montando sobre a nova branch main, via bind, /etc/default/grub, /etc/default/grub-btrfs, e /etc/grub.d do sysadmin. Em caso de falha do pacman, a branch padrão mantém seu status. Cancelar a operação manualmente via ctrl-c, ou respondendo não ao pacman é considerado uma falha, e será tratado como tal.

A atualização do grub.cfg é possivel a partir de base-manager --bootloader-update, e não diretamente pelo grub-mkconfig. Edite /etc/default/grub normalmente em seu overlay, invoque base-manager, e ele cuidará do resto, também fazendo a operação em uma branch transacional e validando a saída da grub.

Base-manager --restore-root provê uma forma simples de tornar qualquer dos branchs disponíveis em PacmanRoot a partir do boot seguinte; é uma operação não destrutiva, as branchs são somente duplicadas e renomeadas.

Com base-manager --edit-pacmanroot, um branch transacional será criado, montado, e plenamente acessível e manuseável conforme o sysadmin desejar, via chroot. Os mesmos binds de pac-base serão montados aqui também. Após saír do chroot, a branch padrão será renomeada, e a branch transacional será tornada como padrão. O sysadmin deve reiniciar e conferir se suas modificações foram bem sucedidas. Em caso contrário, basta usar --restore-root para reverter.

Para editar PacmanRoot sem nenhuma montagem bind, basta, após base-manager --edit-pacmanroot, desmontá-las. Tenha em mente que, caso use o pacman nessa situação, se a cache não for limpa, dali por diante ela será propagada em todas as novas branchs, assim como as modificações. Além disso, no processo de atualizar a grub, todas as montagens bind serão refeitas, portando editar /etc/grub.d e /etc/default/grub diretamente de PacmanRoot (e não nas montagens bind) é inútil.

Já base-manager --use-now, irá montar diretamente a atual branch main, sobre ela os mesmos overlays de sysadmin do boot, e em seguida entrará nela via chroot montando tudo que estiver no fstab, e passando um usuário fornecido. Essa função serve para que algum programa recém adicionado via pac-base seja usado imediatamente (sem reinício). Quase quaisquer programas (mesmo os gráficos) funcionarão, mas evite fazer uso disso. Programas que dependem de serviços não vão funcionar adequadamente. Prefira criar uma DistroBox do ArchLinux e instalar o que precisar ali dentro. Caso não funcione, e um reinício naquele momento for realmente impossível, apele para --use-now.

Base-manager e pac-base por padrão não fazem nenhuma operação destrutiva (sendo scritps simples, seu comportamento pode ser alterado se o sysadmin assim desejar), e buscam ao máximo tratar erros de forma a não deixar o sysadmin sem uma branch main a ser usada no boot seguinte. Por vezes, isso implica em voltar muitas branchs, e tornar o root **atualmente em uso** como upstream, ignorando quantos sejam os branchs à frente que já existam. Exemplo, supondo uma máquina que não é reiniciada a um mês, que foi atualizada a cada 3 dias (via timer rodando pac-base -Syu --noconfirm), gerando 10 novas branchs, caso ocorra um erro na 11ª atualização, a correção de erros de base-manager/pac-base tentará tornar como upstream a branch anterior em que a atualização foi bem sucedida (10ª). Caso isso também falhe, base-manager-/pac-base tentará promover a branch que deu boot na máquina, por considerá-la confiável, e portando ignorando todos os updates subsequentes, sem excluí-los. Uma vez que o timer continue rodando, na 12ª atualização (dia 36), ele tentará aplicar todas as atualizações perdidas numa única nova branch. Leve isso em conta ao automatizar o processo de atualização. Ao perceber que um erro desse tipo ocorreu, confira o dmesg; um erro na geração em si de novas branchs pode indicar problemas na saúde do sistema de arquivos.

Será papel do sysadmin implementar quaisquer políticas que queira de garbage collector dos branchs. No meu uso pessoal, um temporizador systemd roda um script bash a cada 15 dias, e deixa os 20 branchs mais recentes. Outra possibilidade é incluir o garbage collector diretamente em pac-base, de forma que o número de branchs permaneça sempre o mesmo, descartando o branch mais antigo após uma transação bem sucedida, e antes de atualizar o bootloader. Códigos de exemplos serão copiados durante a instalação de Stateless-Arch, mas não serão ativos por padrão.

# Considerações finais <h8>

Um leitor atento já percebeu que a ideia aqui é que PacmanRoot permaneça sempre em "estado de pacstrap": Qualquer nova branch terá somente pacotes do pacman, em seus padrões, somado à pouca configuração (senha root e locales) de /etc geradas durante a instalação; faça todo o resto no overlay do sysadmin, e na sua home, e você poderá enviar um branch de PacmanRoot para outra pessoa/dispositivo ( usando btrfs send/receive, tar, rsycn, ou que for), com a certeza de não enviar junto chaves ssh, senhas de wifi, ou outras informações sensíveis; use base-manager --reset-sysadmin-data, e no boot seguinte o sistema retornará em "modo de fábrica". Outro caso de uso seria uma abordagem semelhante a [Erase your darlings](https://grahamc.com/blog/erase-your-darlings), onde se embute, direto em PacmanRoot, configurações de root consideradas ótimas, e em todo boot, o initrd recria um overlay de sysadmin limpo.  Ou ainda, se estabelece um sysadmin-overlay que deve ser sempre restaurado para um estado conhecido no boot, e ainda assim, pode ser limpo. É fácil converter Stateless Arch para esse propósito (dica, só precisa de duas linhas a mais no initrd, e algumas poucas remoções em base-manager e pac-base), mas deixo essa tarefa para quem se interessar por esse caso de uso.

O sistema dessa forma será altamente resiliente. De fato, excetuando algo que afete diretamente o sistema de arquivos, ou apagar as imagens da grub (mbr do disco se disco mbr+legacy, partição biosboot se gpt+legacy, arquivos da partição fat-32 se efi), o sistema é facilmente recuperável em praticamente qualquer situação sem necessidade de live-boot. Novo kernel/driver de vídeo problemático? Use base-manager --restore-root em um branch anterior. A grub não encontrou o arquivo de configuração e caiu no shell? Use a cli para chamar o configfile de qualquer um dos branchs, todos eles terão um grub.cfg. Grub-rescue? Chame o binário da grub de qualquer um dos branchs, e você terá o grub-shell completo, se onde será possível chamar o grub.cfg de qualquer um dos branchs.

Caso o sysadmin regrida para um branch onde não exista um determinado binário, mas em seu /etc overlay exista uma configuração de serviço que aponte para esse binário, é possível que o boot seja parado. Isso não implica em um branch de PacmanRoot quebrado, somente em uma configuração de serviço do sysadmin que não pode ser honrada. Esse gerenciamento é totalmente delegado ao sysadmin. Em alguns casos, o shell de emergência do boot pode bastar para remover a inconsistência encontrada e permitir que o boot prossiga. Caso contrário, tente iniciar o sistema em branchs anteriores do root. Caso seja impossível estabelecer qual a causa verdadeira do problema rapidamente, o sysadmin pode simplesmente usar base-manager --reset-sysadmin-data a partir do shell de emergência de qualquer branch, que todo o overlay do sysadmin será renomeado (para inspeção futura), e um novo será gerado. Como já dito, deletar o sysadmin overlay é responsabilidade do sysadmin. Se o boot, por qualquer motivo que seja, ficar parado no initrd, é possível a partir do shell dele, fazer manualmente a mesma operação que --reset-sysadmin-data.

Repare que esse projeto se destina a permitir um sistema confiável, mas que ainda assim, seja humanamente modificável e gerenciável, de forma relativamente familiar. Opensuse MicroOS, Fedora SilverBlue e outras, alteram tanto a hierarquia do sistema de arquivos, quanto gerenciadores de pacotes, além dos pacotes em si de seus repositórios, de forma a automatizar muitas das tarefas que nesse projeto são delegadas ás mãos do sysadmin; se você quer um sistema inteiramente autogerenciado, com garantias de funcionalidade, mas não amigável a humanos, vá diretamente para uma das alternativas acima. Stateless Arch é para usuários de ArchLinux que querem desfrutar das vantagens de um sistema sem estado e imutável, mas não abrem mão de conseguir customizar seu sistema manualmente, com pouquíssimo atrito, sem sentir que estão lutando contra o sistema. **Sempre lembrando que, grandes poderes...**.

Assim como no Suse MicroOS, e em qualquer sistema desse tipo, o sistema não é à prova de um sysadmin com nível de acesso root verdadeiro (e não de dentro de um container) que QUEIRA quebrar o sistema. Exemplos simples: troque o nome do subvolume root no Suse MicroOS, e reinicie, e o boot parará no init. Apague a configuração de boot do Clear Linux, e algo parecido ocorrerá. Apague grub.cfg do Fedora Silverblue, e se depare com grub-shell. Em qualquer que seja o sistema, um dd de dev/zero sobre o root o destrói, obviamente. Portanto, não se trata de desafiar o sysadmin a conseguir quebrar uma instalação, e sim de dificultar ao máximo que um sysadmin que quer MANTER uma instalação funcional a perca, e auxiliá-lo a replicar a instalação se necessário.

O uso de Stateles Arch (transacional) da forma em que está nesse momento já é possível , mas se trata de uma ferramenta beta. Mesmo quando for terminada, **NÃO SERÁ** indicada para usuários inexperientes. Problemas que exijam conhecimento de pontos de montagem, manipulação do processo de boot e de subvolumes btrfs podem surgir.

**Podem haver problemas e incompatibilidades que eu não encontrei nos meus testes, e que podem aparecer somente com o uso de determinados programas, ou combinação de programas, ou cenários especiais.**

**A máquina é sua, o sistema de arquivos é seu, a decisão de usar esses scripts foi sua, portanto os riscos e prejuízos são seus.**

**O suporte a luks e a secure-boot não foi testado.**

Para construir rapidamente um setup Stateless Arch focado em utilização de containers (semelhante ao Suse MicroOs e ao Fedora Silverblue), visite [Arch Start](https://github.com/vmath3us/arch-start). Lá estará um espelho da minha própria máquina, de forma que, de posse daquele repositório e desse, minha instalação é reproduzível.

Para imagens de máquina virtual, acesse [Stateless Arch no Telegram](https://t.me/StatelessArch) (após o primeiro boot, clone esse repositório, e cole manualmente os scritps em seus respectivos locais, para garantir que estejam na versão mais recente)
