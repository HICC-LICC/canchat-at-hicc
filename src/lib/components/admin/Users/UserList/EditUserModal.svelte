<script lang="ts">
	import { toast } from 'svelte-sonner';
	import dayjs from 'dayjs';
	import { createEventDispatcher } from 'svelte';
	import { onMount, getContext } from 'svelte';

	import { updateUserById } from '$lib/apis/users';

	import Modal from '$lib/components/common/Modal.svelte';

	const i18n = getContext('i18n');
	const dispatch = createEventDispatcher();

	export let show = false;
	export let selectedUser;
	export let sessionUser;

	let _user = {
		profile_image_url: '',
		name: '',
		email: '',
		password: '',
		role: ''
	};

	const submitHandler = async () => {
		const res = await updateUserById(localStorage.token, selectedUser.id, _user).catch((error) => {
			toast.error(`${error}`);
		});

		if (res) {
			dispatch('save');
			show = false;
		}
	};

	onMount(() => {
		if (selectedUser) {
			_user = selectedUser;
			_user.password = '';
		}
	});
</script>

<Modal size="sm" bind:show returnfocusSelector="#edit-user">
	<div>
		<div class=" flex justify-between dark:text-gray-300 px-5 py-4">
			<div class=" text-lg font-medium self-center">{$i18n.t('Edit User')}</div>
			<button
				class="self-center"
				on:click={() => {
					show = false;
				}}
			>
				<svg
					xmlns="http://www.w3.org/2000/svg"
					viewBox="0 0 20 20"
					fill="currentColor"
					class="w-5 h-5"
				>
					<path
						d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z"
					/>
				</svg>
			</button>
		</div>
		<hr class=" dark:border-gray-800" />

		<div class="flex flex-col md:flex-row w-full p-5 md:space-x-4 dark:text-gray-200">
			<div class=" flex flex-col w-full sm:flex-row sm:justify-center sm:space-x-6">
				<form
					class="flex flex-col w-full"
					on:submit|preventDefault={() => {
						submitHandler();
					}}
				>
					<div class=" flex items-center rounded-md py-2 px-4 w-full">
						<div class=" self-center mr-5">
							<img
								src={selectedUser.profile_image_url}
								class=" max-w-[55px] object-cover rounded-full"
								alt="User profile"
							/>
						</div>

						<div>
							<div class=" self-center capitalize font-semibold">{selectedUser.name}</div>

							<div class="text-xs text-gray-500">
								{$i18n.t('Created at')}
								{dayjs(selectedUser.created_at * 1000).format($i18n.t('MMMM DD, YYYY'))}
							</div>
						</div>
					</div>

					<hr class=" dark:border-gray-800 my-3 w-full" />

					<div class=" flex flex-col space-y-1.5">
						<div class="flex flex-col w-full">
							<div class=" mb-1 text-xs text-gray-500">{$i18n.t('Role')}</div>

							<div class="flex-1">
								<select
									class="w-full capitalize rounded-lg py-2 px-4 text-sm dark:text-gray-300 dark:bg-gray-800 outline-none"
									bind:value={_user.role}
									disabled={_user.id == sessionUser.id}
								>
									<option value="pending"> {$i18n.t('pending')} </option>
									<option value="user"> {$i18n.t('user')} </option>
									<option value="analyst"> {$i18n.t('analyst')} </option>
									<option value="global_analyst"> {$i18n.t('global analyst')} </option>
									<option value="admin"> {$i18n.t('admin')} </option>
								</select>
							</div>
						</div>

						<div class="flex flex-col w-full">
							<div class=" mb-1 text-xs text-gray-500">{$i18n.t('Email')}</div>

							<div class="flex-1">
								<input
									class="w-full rounded py-2 px-4 text-sm dark:text-gray-300 dark:bg-gray-800 disabled:text-gray-500 dark:disabled:text-gray-500 outline-none"
									type="email"
									bind:value={_user.email}
									autocomplete="off"
									required
									disabled={_user.id == sessionUser.id}
								/>
							</div>
						</div>

						<div class="flex flex-col w-full">
							<div class=" mb-1 text-xs text-gray-500">{$i18n.t('Name')}</div>

							<div class="flex-1">
								<input
									class="w-full rounded py-2 px-4 text-sm dark:text-gray-300 dark:bg-gray-800 outline-none"
									type="text"
									bind:value={_user.name}
									autocomplete="off"
									required
								/>
							</div>
						</div>

						<div class="flex flex-col w-full">
							<div class=" mb-1 text-xs text-gray-500">{$i18n.t('New Password')}</div>

							<div class="flex-1">
								<input
									class="w-full rounded py-2 px-4 text-sm dark:text-gray-300 dark:bg-gray-800 outline-none"
									type="password"
									bind:value={_user.password}
									autocomplete="new-password"
								/>
							</div>
						</div>
					</div>

					<div class="flex justify-end pt-3 text-sm font-medium">
						<button
							class=" px-4 py-2 bg-emerald-700 hover:bg-emerald-800 text-gray-100 transition rounded-lg"
							type="submit"
						>
							{$i18n.t('Save')}
						</button>
					</div>
				</form>
			</div>
		</div>
	</div>
</Modal>

<style>
	input::-webkit-outer-spin-button,
	input::-webkit-inner-spin-button {
		/* display: none; <- Crashes Chrome on hover */
		-webkit-appearance: none;
		margin: 0; /* <-- Apparently some margin are still there even though it's hidden */
	}

	.tabs::-webkit-scrollbar {
		display: none; /* for Chrome, Safari and Opera */
	}

	.tabs {
		-ms-overflow-style: none; /* IE and Edge */
		scrollbar-width: none; /* Firefox */
	}

	input[type='number'] {
		-moz-appearance: textfield; /* Firefox */
	}
</style>
