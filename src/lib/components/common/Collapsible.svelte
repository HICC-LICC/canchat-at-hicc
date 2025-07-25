<script lang="ts">
	import { getContext, createEventDispatcher } from 'svelte';
	const i18n = getContext('i18n');

	import dayjs from '$lib/dayjs';
	import duration from 'dayjs/plugin/duration';
	import relativeTime from 'dayjs/plugin/relativeTime';

	dayjs.extend(duration);
	dayjs.extend(relativeTime);

	async function loadLocale(locales) {
		for (const locale of locales) {
			try {
				dayjs.locale(locale);
				break; // Stop after successfully loading the first available locale
			} catch (error) {
				console.error(`Could not load locale '${locale}':`, error);
			}
		}
	}

	// Assuming $i18n.languages is an array of language codes
	$: loadLocale($i18n.languages);

	const dispatch = createEventDispatcher();
	$: dispatch('change', open);

	import { slide } from 'svelte/transition';
	import { quintOut } from 'svelte/easing';

	import ChevronUp from '../icons/ChevronUp.svelte';
	import ChevronDown from '../icons/ChevronDown.svelte';
	import Spinner from './Spinner.svelte';
	import { ariaMessage } from '$lib/stores';

	export let open = false;
	export let className = '';
	export let buttonClassName =
		'w-fit text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 transition';
	export let title = null;
	export let attributes = null;

	export let grow = false;

	export let disabled = false;
	export let hide = false;

	let initialized = false;

	const announceAction = (open: boolean) => {
		if (open) {
			ariaMessage.set($i18n.t('expanded'));
		} else {
			ariaMessage.set($i18n.t('collapsed'));
		}
	};
</script>

<div class={className}>
	{#if title !== null}
		<!-- svelte-ignore a11y-no-static-element-interactions -->
		<!-- svelte-ignore a11y-click-events-have-key-events -->
		<div
			class="{buttonClassName} cursor-pointer"
			tabindex="0"
			on:pointerup={() => {
				if (!disabled) {
					open = !open;
					announceAction(open);
				}
			}}
			on:keydown={(e) => {
				if (!disabled && (e.key === 'Enter' || e.key === ' ')) {
					e.preventDefault();
					open = !open;
					announceAction(open);
				}
			}}
		>
			<div
				class=" w-full font-medium flex items-center justify-between gap-2 {attributes?.done &&
				attributes?.done !== 'true'
					? 'shimmer'
					: ''}
			"
			>
				{#if attributes?.done && attributes?.done !== 'true'}
					<div>
						<Spinner className="size-4" />
					</div>
				{/if}

				<div class="">
					{#if attributes?.type === 'reasoning'}
						{#if attributes?.done === 'true' && attributes?.duration}
							{$i18n.t('Thought for {{DURATION}}', {
								DURATION: dayjs.duration(attributes.duration, 'seconds').humanize()
							})}
						{:else}
							{$i18n.t('Thinking...')}
						{/if}
					{:else}
						<h3>{title}</h3>
					{/if}
				</div>

				<div class="flex self-center translate-y-[1px]">
					{#if open}
						<ChevronUp strokeWidth="3.5" className="size-3.5" />
					{:else}
						<ChevronDown strokeWidth="3.5" className="size-3.5" />
					{/if}
				</div>
			</div>
		</div>
	{:else}
		<!-- svelte-ignore a11y-no-static-element-interactions -->
		<!-- svelte-ignore a11y-click-events-have-key-events -->
		<div
			class="{buttonClassName} cursor-pointer"
			on:pointerup={() => {
				if (!disabled) {
					open = !open;
					announceAction(open);
				}
			}}
			on:keydown={(e) => {
				if (!disabled && (e.key === 'Enter' || e.key === ' ')) {
					e.preventDefault();
					open = !open;
					announceAction(open);
				}
			}}
		>
			<div>
				<slot />

				{#if grow}
					{#if open && !hide}
						<div
							transition:slide={{ duration: 300, easing: quintOut, axis: 'y' }}
							on:pointerup={(e) => {
								e.stopPropagation();
							}}
						>
							<slot name="content" />
						</div>
					{/if}
				{/if}
			</div>
		</div>
	{/if}

	{#if !grow}
		{#if open && !hide}
			<div transition:slide={{ duration: 300, easing: quintOut, axis: 'y' }}>
				<slot name="content" />
			</div>
		{/if}
	{/if}
</div>
