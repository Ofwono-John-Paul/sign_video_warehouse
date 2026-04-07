"""add video conversion columns

Revision ID: b7f0e6b6c4a1
Revises: aacbde9910d6
Create Date: 2026-04-07 00:00:00.000000

"""
from alembic import op


# revision identifiers, used by Alembic.
revision = 'b7f0e6b6c4a1'
down_revision = 'aacbde9910d6'
branch_labels = None
depends_on = None


def upgrade():
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'videos'
            ) THEN
                ALTER TABLE public.videos
                    ADD COLUMN IF NOT EXISTS original_format VARCHAR(50),
                    ADD COLUMN IF NOT EXISTS conversion_status VARCHAR(20);

                UPDATE public.videos
                SET conversion_status = COALESCE(conversion_status, 'converted')
                WHERE conversion_status IS NULL;
            END IF;
        END $$;
        """
    )


def downgrade():
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = 'videos'
            ) THEN
                ALTER TABLE public.videos
                    DROP COLUMN IF EXISTS conversion_status,
                    DROP COLUMN IF EXISTS original_format;
            END IF;
        END $$;
        """
    )
