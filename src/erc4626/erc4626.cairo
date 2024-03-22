#[starknet::contract]
mod ERC4626 {
    use erc4626::erc4626::interface::{
        IERC4626, IERC4626Additional, IERC4626Snake, IERC4626Camel, IERC4626Metadata
    };
    use erc4626::utils::{pow_256};
    use integer::BoundedU256;
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Metadata, ERC20ABIDispatcher, ERC20ABIDispatcherTrait
    };
    use openzeppelin::token::erc20::{ERC20Component, ERC20Component::Errors as ERC20Errors};

    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;

    #[storage]
    struct Storage {
        asset: ContractAddress,
        underlying_decimals: u8,
        offset: u8,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        sender: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        sender: ContractAddress,
        #[key]
        receiver: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256
    }

    mod Errors {
        const EXCEEDED_MAX_DEPOSIT: felt252 = 'ERC4626: exceeded max deposit';
        const EXCEEDED_MAX_MINT: felt252 = 'ERC4626: exceeded max mint';
        const EXCEEDED_MAX_REDEEM: felt252 = 'ERC4626: exceeded max redeem';
        const EXCEEDED_MAX_WITHDRAW: felt252 = 'ERC4626: exceeded max withdraw';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, asset: ContractAddress, name: ByteArray, symbol: ByteArray, offset: u8
    ) {
        let dispatcher = ERC20ABIDispatcher { contract_address: asset };
        self.offset.write(offset);
        let decimals = dispatcher.decimals();
        self.erc20.initializer(name, symbol);
        self.asset.write(asset);
        self.underlying_decimals.write(decimals);
    }


    #[embeddable_as(ERC4626AdditionalImpl)]
    impl ERC4626Additional<
        TContractState, +HasComponent<TContractState>
    > of IERC4626Additional<ComponentState<TContractState>> {
        fn asset(self: @ComponentState<TContractState>) -> ContractAddress {
            self.asset.read()
        }

        fn convert_to_assets(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            self._convert_to_assets(shares, false)
        }

        fn convert_to_shares(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            self._convert_to_shares(assets, false)
        }

        fn deposit(ref self: ComponentState<TContractState>, assets: u256, receiver: ContractAddress) -> u256 {
            let max_assets = self.max_deposit(receiver);
            assert(max_assets >= assets, Errors::EXCEEDED_MAX_DEPOSIT);

            let caller = get_caller_address();
            let shares = self.preview_deposit(assets);
            self._deposit(caller, receiver, assets, shares);

            shares
        }

        fn max_deposit(self: @ComponentState<TContractState>, address: ContractAddress) -> u256 {
            BoundedU256::max()
        }

        fn max_mint(self: @ComponentState<TContractState>, receiver: ContractAddress) -> u256 {
            BoundedU256::max()
        }

        fn max_redeem(self: @ComponentState<TContractState>, owner: ContractAddress) -> u256 {
            self.balance_of(owner)
        }

        fn max_withdraw(self: @ComponentState<TContractState>, owner: ContractAddress) -> u256 {
            let balance = self.balance_of(owner);
            self._convert_to_assets(balance, false)
        }

        fn mint(ref self: ComponentState<TContractState>, shares: u256, receiver: ContractAddress) -> u256 {
            let max_shares = self.max_mint(receiver);
            assert(max_shares >= shares, Errors::EXCEEDED_MAX_MINT);

            let caller = get_caller_address();
            let assets = self.preview_mint(shares);
            self._deposit(caller, receiver, assets, shares);

            assets
        }

        fn preview_deposit(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            self._convert_to_shares(assets, false)
        }

        fn preview_mint(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            self._convert_to_assets(shares, true)
        }

        fn preview_redeem(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            self._convert_to_assets(shares, false)
        }

        fn preview_withdraw(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            self._convert_to_shares(assets, true)
        }

        fn redeem(
            ref self: ComponentState<TContractState>, shares: u256, receiver: ContractAddress, owner: ContractAddress
        ) -> u256 {
            let max_shares = self.max_redeem(owner);
            assert(shares <= max_shares, Errors::EXCEEDED_MAX_REDEEM);

            let caller = get_caller_address();
            let assets = self.preview_redeem(shares);
            self._withdraw(caller, receiver, owner, assets, shares);
            assets
        }

        fn total_assets(self: @ComponentState<TContractState>) -> u256 {
            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.balance_of(get_contract_address())
        }

        fn withdraw(
            ref self: ComponentState<TContractState>, assets: u256, receiver: ContractAddress, owner: ContractAddress
        ) -> u256 {
            let max_assets = self.max_withdraw(owner);
            assert(assets <= max_assets, Errors::EXCEEDED_MAX_WITHDRAW);

            let caller = get_caller_address();
            let shares = self.preview_withdraw(assets);
            self._withdraw(caller, receiver, owner, assets, shares);

            shares
        }
    }


    #[embeddable_as(MetadataEntrypointsImpl)]
    impl MetadataEntrypoints<
        TContractState, +HasComponent<TContractState>
    > of IERC4626Metadata<ComponentState<TContractState>> {
        fn name(self: @ComponentState<TContractState>) -> ByteArray {
            self.erc20.name()
        }
        fn symbol(self: @ComponentState<TContractState>) -> ByteArray {
            self.erc20.symbol()
        }
        fn decimals(self: @ComponentState<TContractState>) -> u8 {
            self.underlying_decimals.read() + self._decimals_offset()
        }
    }

    #[embeddable_as(SnakeEntrypointsImpl)]
    impl SnakeEntrypoints<
        TContractState, +HasComponent<TContractState>
    > of IERC4626Snake<ComponentState<TContractState>> {
        fn total_supply(self: @ComponentState<TContractState>) -> u256 {
            self.erc20.total_supply()
        }

        fn balance_of(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.erc20.balance_of(account)
        }

        fn allowance(
            self: @ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.allowance(owner, spender)
        }

        fn transfer(ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20.transfer(recipient, amount)
        }

        fn transfer_from(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            self.erc20.transfer_from(sender, recipient, amount)
        }

        fn approve(ref self: ComponentState<TContractState>, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }
    }

    #[embeddable_as(CamelEntrypointsImpl)]
    impl CamelEntrypoints<
        TContractState, +HasComponent<TContractState>
    > of IERC4626Camel<ComponentState<TContractState>> {
        fn totalSupply(self: @ComponentState<TContractState>) -> u256 {
            self.total_supply()
        }
        fn balanceOf(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            self.transfer_from(sender, recipient, amount)
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalImplTrait {
        fn _convert_to_assets(self: @ContractState, shares: u256, round: bool) -> u256 {
            let total_assets = self.total_assets() + 1;
            let total_shares = self.total_supply() + pow_256(10, self._decimals_offset());
            let assets = shares * total_assets / total_shares;
            if round && ((assets * total_shares) / total_assets < shares) {
                assets + 1
            } else {
                assets
            }
        }

        fn _convert_to_shares(self: @ContractState, assets: u256, round: bool) -> u256 {
            let total_assets = self.total_assets() + 1;
            let total_shares = self.total_supply() + pow_256(10, self._decimals_offset());
            let share = assets * total_shares / total_assets;
            if round && ((share * total_assets) / total_shares < assets) {
                share + 1
            } else {
                share
            }
        }

        fn _deposit(
            ref self: ContractState,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256
        ) {
            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.transfer_from(caller, get_contract_address(), assets);
            self.erc20._mint(receiver, shares);
            self.emit(Deposit { sender: caller, owner: receiver, assets, shares });
        }

        fn _withdraw(
            ref self: ContractState,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256
        ) {
            if (caller != owner) {
                let allowance = self.allowance(owner, caller);
                if (allowance != BoundedU256::max()) {
                    assert(allowance >= shares, ERC20Errors::APPROVE_FROM_ZERO);
                    self.erc20.ERC20_allowances.write((owner, caller), allowance - shares);
                }
            }

            self.erc20._burn(owner, shares);

            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.transfer(receiver, assets);

            self.emit(Withdraw { sender: caller, receiver, owner, assets, shares });
        }

        fn _decimals_offset(self: @ContractState) -> u8 {
            self.offset.read()
        }
    }
}
