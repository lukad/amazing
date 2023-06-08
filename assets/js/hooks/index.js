import * as maze from "./hooks/maze";

export const Hooks = {
  Maze: {
    mounted() {
      maze.setup.bind(this)(this.el);
    },
  },
};
