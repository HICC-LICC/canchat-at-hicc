<script lang="ts">
	import Bolt from '$lib/components/icons/Bolt.svelte';
	import { onMount, getContext, createEventDispatcher } from 'svelte';
	import { suggestionCycle } from '$lib/stores/index';

	const i18n = getContext('i18n');
	const dispatch = createEventDispatcher();

	export let suggestionPrompts = [];
	export let className = '';

	let prompts = [];

	// Single function to handle shuffling
	const shuffleSuggestions = (suggestions) => {
		return [...(suggestions ?? [])]
			.flat() // Replace reduce/spread with flat()
			.sort(() => Math.random() - 0.5);
	};

	// Reshuffle when suggestionCycle changes or suggestions update
	$: {
		$suggestionCycle; // Just use to trigger reactivity
		prompts = shuffleSuggestions(suggestionPrompts);
	}
</script>

{#if prompts.length > 0}
	<h2 class="mb-1 flex gap-1 text-xs font-medium items-center text-gray-600 dark:text-gray-500">
		<Bolt />
		{$i18n.t('Suggested')}
	</h2>
{/if}

<div class=" h-40 max-h-full overflow-auto scrollbar-none {className}">
	{#each prompts as prompt, promptIdx}
		{#if prompt.lang == $i18n.language}
			<button
				class="flex flex-col flex-1 shrink-0 w-full justify-between px-3 py-2 rounded-xl bg-transparent hover:bg-black/5 dark:hover:bg-white/5 transition group text-left"
				on:click={() => {
					dispatch('select', prompt.content);
				}}
			>
				<span
					class="font-medium text-gray-600 dark:text-gray-300 dark:group-hover:text-gray-200 transition line-clamp-1"
				>
					{#if prompt.title && prompt.title[0] !== ''}
						{$i18n.t(prompt.title[0])}
					{:else}
						{$i18n.t(prompt.content)}
					{/if}
				</span>
				{#if prompt.title && prompt.title[1]}
					<span class="text-xs text-gray-600 dark:text-gray-300 font-normal line-clamp-1">
						{$i18n.t(prompt.title[1])}
					</span>
				{/if}
			</button>
		{/if}
	{/each}
</div>
